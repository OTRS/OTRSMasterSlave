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

        # do not check RichText
        $SysConfigObject->ConfigItemUpdate(
            Valid => 1,
            Key   => 'Frontend::RichText',
            Value => 0
        );

        # do not check service and type
        $SysConfigObject->ConfigItemUpdate(
            Valid => 1,
            Key   => 'Ticket::Service',
            Value => 0
        );
        $SysConfigObject->ConfigItemUpdate(
            Valid => 1,
            Key   => 'Ticket::Type',
            Value => 0
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

        # add test customer for testing
        my $TestCustomerPhone = $Helper->TestCustomerUserCreate();

        # get script alias
        my $ScriptAlias = $Kernel::OM->Get('Kernel::Config')->Get('ScriptAlias');

        # naviage to AgentTicketPhone screen
        $Selenium->get("${ScriptAlias}index.pl?Action=AgentTicketPhone");

        # create master test phone ticket
        my $AutoCompleteStringPhone
            = "\"$TestCustomerPhone $TestCustomerPhone\" <$TestCustomerPhone\@localunittest.com> ($TestCustomerPhone)";
        my $MasterTicketSubject = "Master Ticket";
        $Selenium->find_element( "#FromCustomer", 'css' )->send_keys($TestCustomerPhone);
        $Selenium->WaitFor( JavaScript => 'return $("li.ui-menu-item:visible").length' );
        $Selenium->find_element("//*[text()='$AutoCompleteStringPhone']")->click();
        $Selenium->execute_script("\$('#Dest').val('2||Raw').trigger('redraw.InputField').trigger('change');");
        $Selenium->find_element( "#Subject",                         'css' )->send_keys($MasterTicketSubject);
        $Selenium->find_element( "#RichText",                        'css' )->send_keys('Selenium body test');
        $Selenium->find_element( "#DynamicField_MasterSlave_Search", 'css' )->click();
        $Selenium->WaitFor( JavaScript => 'return $("a.jstree-anchor:visible").length' );
        $Selenium->find_element("//*[text()='New Master Ticket']")->click();
        $Selenium->find_element("//button[\@id='submitRichText'][\@type='submit']")->click();

        # Wait until form has loaded, if neccessary
        $Selenium->WaitFor( JavaScript => 'return $("form").length' );

        # get ticket object
        my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');

        # get master test phone ticket data
        my %MasterTicketIDs = $TicketObject->TicketSearch(
            Result         => 'HASH',
            Limit          => 1,
            CustomerUserID => $TestCustomerPhone,
        );
        my $MasterTicketNumber = (%MasterTicketIDs)[1];
        my $MasterTicketID     = (%MasterTicketIDs)[0];

        # add new test customer for testing
        my $TestCustomerEmail = $Helper->TestCustomerUserCreate();

        # navigate to AgentTicketEmail screen
        $Selenium->get("${ScriptAlias}index.pl?Action=AgentTicketEmail");

        # create slave test email ticket
        my $AutoCompleteStringEmail
            = "\"$TestCustomerEmail $TestCustomerEmail\" <$TestCustomerEmail\@localunittest.com> ($TestCustomerEmail)";
        my $SlaveAutoComplete = "Slave of Ticket#$MasterTicketNumber: $MasterTicketSubject";
        $Selenium->execute_script("\$('#Dest').val('2||Raw').trigger('redraw.InputField').trigger('change');");
        $Selenium->find_element( "#ToCustomer", 'css' )->send_keys($TestCustomerEmail);
        $Selenium->WaitFor( JavaScript => 'return $("li.ui-menu-item:visible").length' );
        $Selenium->find_element("//*[text()='$AutoCompleteStringEmail']")->click();
        $Selenium->find_element( "#Subject",                         'css' )->send_keys('Slave Ticket');
        $Selenium->find_element( "#RichText",                        'css' )->send_keys('Selenium body test');
        $Selenium->find_element( "#DynamicField_MasterSlave_Search", 'css' )->click();
        $Selenium->WaitFor( JavaScript => 'return $("a.jstree-anchor:visible").length' );
        $Selenium->find_element("//*[text()='$SlaveAutoComplete']")->click();
        $Selenium->find_element("//button[\@id='submitRichText'][\@type='submit']")->click();

        # Wait until form has loaded, if neccessary
        $Selenium->WaitFor( JavaScript => 'return $("form").length' );

        # get slave test email ticket data
        my %SlaveTicketIDs = $TicketObject->TicketSearch(
            Result         => 'HASH',
            Limit          => 1,
            CustomerUserID => $TestCustomerEmail,
        );
        my $SlaveTicketNumber = (%SlaveTicketIDs)[1];
        my $SlaveTicketID     = (%SlaveTicketIDs)[0];

        # naviage to ticket zoom page of created master test ticket
        $Selenium->get("${ScriptAlias}index.pl?Action=AgentTicketZoom;TicketID=$MasterTicketID");

        # verify master-slave ticket link
        $Self->True(
            index( $Selenium->get_page_source(), $SlaveTicketNumber ) > -1,
            "Slave ticket number: $SlaveTicketNumber - found",
        );

        # navigate to history view of created master test ticket
        $Selenium->get("${ScriptAlias}index.pl?Action=AgentTicketHistory;TicketID=$MasterTicketID");

        # verify dynamic field master ticket update
        $Self->True(
            index( $Selenium->get_page_source(), 'FieldName=MasterSlave;Value=Master' ) > -1,
            "Master dynamic field update value - found",
        );

        # naviage to ticket zoom page of created slave test ticket
        $Selenium->get("${ScriptAlias}index.pl?Action=AgentTicketZoom;TicketID=$SlaveTicketID");

        # verify slave-master ticket link
        $Self->True(
            index( $Selenium->get_page_source(), $MasterTicketNumber ) > -1,
            "Master ticket number: $MasterTicketNumber - found",
        );

        # navigate to history view of created slave test ticket
        $Selenium->get("${ScriptAlias}index.pl?Action=AgentTicketHistory;TicketID=$SlaveTicketID");

        # verify dynamic field slave ticket update
        $Self->True(
            index( $Selenium->get_page_source(), "FieldName=MasterSlave;Value=SlaveOf:$MasterTicketNumber" ) > -1,
            "Slave dynamic field update value - found",
        );

        # delete created test tickets
        for my $TicketID ( $MasterTicketID, $SlaveTicketID ) {
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
