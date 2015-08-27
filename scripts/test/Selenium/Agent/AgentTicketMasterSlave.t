# --
# Copyright (C) 2001-2015 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

use strict;
use warnings;
use utf8;

use vars (qw($Self));

# get selenium object
my $Selenium = $Kernel::OM->Get('Kernel::System::UnitTest::Selenium');

$Selenium->RunTest(
    sub {

        # get helper object
        $Kernel::OM->ObjectParamAdd(
            'Kernel::System::UnitTest::Helper' => {
                RestoreSystemConfiguration => 1,
            },
        );
        my $Helper = $Kernel::OM->Get('Kernel::System::UnitTest::Helper');

        # get sysconfig object
        my $SysConfigObject = $Kernel::OM->Get('Kernel::System::SysConfig');

        # enable the advanced MasterSlave
        $SysConfigObject->ConfigItemUpdate(
            Valid => 1,
            Key   => 'MasterSlave::AdvancedEnabled',
            Value => 1
        );

        # enable change the MasterSlave state of a ticket
        $SysConfigObject->ConfigItemUpdate(
            Valid => 1,
            Key   => 'MasterSlave::UpdateMasterSlave',
            Value => 1
        );

        # do not check RichText
        $SysConfigObject->ConfigItemUpdate(
            Valid => 1,
            Key   => 'Frontend::RichText',
            Value => 0
        );

        # get ticket object
        my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');

        # create two test tickets
        my @TicketIDs;
        my @TicketNumbers;
        for my $TicketCreate ( 1 .. 2 ) {
            my $TicketNumber = $TicketObject->TicketCreateNumber();
            my $TicketID     = $TicketObject->TicketCreate(
                TN           => $TicketNumber,
                Title        => 'Selenium Ticket',
                Queue        => 'Raw',
                Lock         => 'unlock',
                Priority     => '3 normal',
                StateID      => 1,
                TypeID       => 1,
                CustomerID   => 'SeleniumCustomer',
                CustomerUser => 'customer@example.com',
                OwnerID      => 1,
                UserID       => 1,
            );
            $Self->True(
                $TicketID,
                "Ticket ID $TicketID - created",
            );

            push @TicketIDs,     $TicketID;
            push @TicketNumbers, $TicketNumber;
        }

        # create test user and login
        my $TestUserLogin = $Helper->TestUserCreate(
            Groups => [ 'admin', 'users' ],
        ) || die "Did not get test user";

        $Selenium->Login(
            Type     => 'Agent',
            User     => $TestUserLogin,
            Password => $TestUserLogin,
        );

        # get script alias
        my $ScriptAlias = $Kernel::OM->Get('Kernel::Config')->Get('ScriptAlias');

        # naviage to ticket zoom page of first created test ticket
        $Selenium->get("${ScriptAlias}index.pl?Action=AgentTicketZoom;TicketID=$TicketIDs[0]");

        # click on MasterSlave and switch window
        $Selenium->find_element("//a[contains(\@href, \'Action=AgentTicketMasterSlave' )]")->click();

        my $Handles = $Selenium->get_window_handles();
        $Selenium->switch_to_window( $Handles->[1] );

        # check AgentTicketMasterSlave screen
        for my $ID (
            qw(DynamicField_MasterSlave Subject RichText FileUpload ArticleTypeID_Search submitRichText)
            )
        {
            my $Element = $Selenium->find_element( "#$ID", 'css' );
            $Element->is_enabled();
            $Element->is_displayed();
        }

        # set first test ticket as master ticket
        $Selenium->find_element( "#DynamicField_MasterSlave_Search", 'css' )->click();
        $Selenium->WaitFor( JavaScript => 'return $("a.jstree-anchor:visible").length' );
        $Selenium->find_element("//*[text()='New Master Ticket']")->click();
        $Selenium->find_element( "#RichText", 'css' )->send_keys('Selenium Master Ticket');
        $Selenium->find_element("//button[\@id='submitRichText'][\@type='submit']")->click();

        $Selenium->switch_to_window( $Handles->[0] );

        # navigate to history view of created master test ticket
        $Selenium->get("${ScriptAlias}index.pl?Action=AgentTicketHistory;TicketID=$TicketIDs[0]");

        # verify dynamic field master ticket update
        $Self->True(
            index( $Selenium->get_page_source(), 'FieldName=MasterSlave;Value=Master' ) > -1,
            "Master dynamic field update value - found",
        );

        # naviage to ticket zoom page of second created test ticket
        $Selenium->get("${ScriptAlias}index.pl?Action=AgentTicketZoom;TicketID=$TicketIDs[1]");

        # click on MasterSlave and switch window
        $Selenium->find_element("//a[contains(\@href, \'Action=AgentTicketMasterSlave' )]")->click();

        $Handles = $Selenium->get_window_handles();
        $Selenium->switch_to_window( $Handles->[1] );

        my $SlaveAutoComplete = "Slave of Ticket#$TicketNumbers[0]: Selenium Ticket";
        $Selenium->find_element( "#DynamicField_MasterSlave_Search", 'css' )->click();
        $Selenium->WaitFor( JavaScript => 'return $("a.jstree-anchor:visible").length' );
        $Selenium->find_element("//*[text()='$SlaveAutoComplete']")->click();
        $Selenium->find_element( "#RichText", 'css' )->send_keys('Selenium Slave Ticket');
        $Selenium->find_element("//button[\@id='submitRichText'][\@type='submit']")->click();

        $Selenium->switch_to_window( $Handles->[0] );

        # navigate to history view of created slave test ticket
        $Selenium->get("${ScriptAlias}index.pl?Action=AgentTicketHistory;TicketID=$TicketIDs[1]");

        # verify dynamic field slave ticket update
        $Self->True(
            index( $Selenium->get_page_source(), "FieldName=MasterSlave;Value=SlaveOf:$TicketNumbers[0]" ) > -1,
            "Slave dynamic field update value - found",
        );

        # delete created test tickets
        for my $TicketID (@TicketIDs) {
            my $Success = $TicketObject->TicketDelete(
                TicketID => $TicketID,
                UserID   => 1,
            );
            $Self->True(
                $Success,
                "Ticket ID $TicketID - deleted"
            );
        }

        # make sure the cache is correct.
        $Kernel::OM->Get('Kernel::System::Cache')->CleanUp( Type => 'Ticket' );

    }
);

1;
