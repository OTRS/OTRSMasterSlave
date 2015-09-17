# --
# Copyright (C) 2001-2015 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

## no critic (Modules::RequireExplicitPackage)
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

        # get SysConfig object
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

        # create test user and login
        my $TestUserLogin = $Helper->TestUserCreate(
            Groups => [ 'admin', 'users' ],
        ) || die "Did not get test user";

        $Selenium->Login(
            Type     => 'Agent',
            User     => $TestUserLogin,
            Password => $TestUserLogin,
        );

        # get test user ID
        my $TestUserID = $Kernel::OM->Get('Kernel::System::User')->UserLookup(
            UserLogin => $TestUserLogin,
        );

        # get ticket object
        my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');

        # create three test tickets
        my @TicketIDs;
        my @TicketNumbers;
        my $TicketTitle = 'MasterSlave ' . $Helper->GetRandomID();
        for my $TicketCreate ( 1 .. 3 ) {
            my $TicketNumber = $TicketObject->TicketCreateNumber();
            my $TicketID     = $TicketObject->TicketCreate(
                TN           => $TicketNumber,
                Title        => $TicketTitle,
                Queue        => 'Raw',
                Lock         => 'unlock',
                Priority     => '3 normal',
                StateID      => 1,
                TypeID       => 1,
                CustomerID   => 'SeleniumCustomer',
                CustomerUser => 'customer@example.com',
                OwnerID      => $TestUserID,
                UserID       => $TestUserID,
            );
            $Self->True(
                $TicketID,
                "Ticket ID $TicketID - created",
            );

            push @TicketIDs,     $TicketID;
            push @TicketNumbers, $TicketNumber;
        }

        # get script alias
        my $ScriptAlias = $Kernel::OM->Get('Kernel::Config')->Get('ScriptAlias');

        # navigate to AgentTicketSearch
        $Selenium->get("${ScriptAlias}index.pl?Action=AgentTicketSearch");

        # wait until form has loaded, if necessary
        $Selenium->WaitFor( JavaScript => "return typeof(\$) === 'function' && \$('#SearchProfile').length" );

        # search test created tickets by title
        $Selenium->execute_script("\$('#Attribute').val('Title').trigger('redraw.InputField').trigger('change');");
        $Selenium->find_element( ".AddButton", 'css' )->click();
        $Selenium->find_element( "Title",      'name' )->send_keys($TicketTitle);
        $Selenium->find_element("//button[\@id='SearchFormSubmit'][\@value='Run search']")->click();

        # select first test created ticket
        $Selenium->find_element("//input[\@value='$TicketIDs[0]']")->click();

        # click on bulk and switch screen
        $Selenium->find_element( "Bulk", 'link_text' )->click();

        my $Handles = $Selenium->get_window_handles();
        $Selenium->switch_to_window( $Handles->[1] );
        $Selenium->WaitFor( WindowCount => 2 );

        # set test ticket as master ticket
        $Selenium->execute_script(
            "\$('#DynamicField_MasterSlave').val('Master').trigger('redraw.InputField').trigger('change');"
        );
        $Selenium->find_element("//button[\@id='submitRichText'][\@type='submit']")->click();

        $Selenium->switch_to_window( $Handles->[0] );
        $Selenium->WaitFor( WindowCount => 1 );
        sleep 1;

        # select second and third test created ticket
        $Selenium->find_element("//input[\@value='$TicketIDs[1]']")->click();
        $Selenium->find_element("//input[\@value='$TicketIDs[2]']")->click();

        # click on bulk and switch screen
        $Selenium->find_element( "Bulk", 'link_text' )->click();

        $Handles = $Selenium->get_window_handles();
        $Selenium->switch_to_window( $Handles->[1] );
        $Selenium->WaitFor( WindowCount => 2 );

        # set test tickets as slave tickets
        my $SlaveAutoComplete = "Slave of Ticket#$TicketNumbers[0]: $TicketTitle";
        $Selenium->execute_script(
            "\$('#DynamicField_MasterSlave').val('SlaveOf:$TicketNumbers[0]').trigger('redraw.InputField').trigger('change');"
        );
        $Selenium->find_element("//button[\@id='submitRichText'][\@type='submit']")->click();

        $Selenium->switch_to_window( $Handles->[0] );
        $Selenium->WaitFor( WindowCount => 1 );

        # navigate to master ticket zoom view
        $Selenium->get("${ScriptAlias}index.pl?Action=AgentTicketZoom;TicketID=$TicketIDs[0]");

        # verify master-slave ticket link
        $Self->True(
            index( $Selenium->get_page_source(), $TicketNumbers[1] ) > -1,
            "Slave ticket number: $TicketNumbers[1] - found",
        );
        $Self->True(
            index( $Selenium->get_page_source(), $TicketNumbers[2] ) > -1,
            "Slave ticket number: $TicketNumbers[2] - found",
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
        $Kernel::OM->Get('Kernel::System::Cache')->CleanUp(
            Type => 'Ticket',
        );
    }

);

1;
