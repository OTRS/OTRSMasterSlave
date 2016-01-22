# --
# Copyright (C) 2001-2016 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

use strict;
use warnings;
use utf8;

use vars (qw($Self));

# get needed objects
my $TicketObject            = $Kernel::OM->Get('Kernel::System::Ticket');
my $DynamicFieldValueObject = $Kernel::OM->Get('Kernel::System::DynamicFieldValue');
my $LinkObject              = $Kernel::OM->Get('Kernel::System::LinkObject');
my $DynamicFieldObject      = $Kernel::OM->Get('Kernel::System::DynamicField');
my $UserObject              = $Kernel::OM->Get('Kernel::System::User');
my $CustomerUserObject      = $Kernel::OM->Get('Kernel::System::CustomerUser');
my $ConfigObject            = $Kernel::OM->Get('Kernel::Config');

# start RestoreDatabse
$Kernel::OM->ObjectParamAdd(
    'Kernel::System::UnitTest::Helper' => {
        RestoreDatabase => 1,
    },
);
my $HelperObject = $Kernel::OM->Get('Kernel::System::UnitTest::Helper');

# ------------------------------------------------------------ #
# make preparations
# ------------------------------------------------------------ #

# enable config MasterSlave::ForwardSlaves
$ConfigObject->Set(
    Key   => 'MasterSlave::ForwardSlaves',
    Value => 1,
);

# get random ID
my $RandomID = $HelperObject->GetRandomID();

# get master/slave dynamic field data
my $MasterSlaveDynamicField     = $ConfigObject->Get('MasterSlave::DynamicField');
my $MasterSlaveDynamicFieldData = $DynamicFieldObject->DynamicFieldGet(
    Name => $MasterSlaveDynamicField,
);

# create new user
my $TestUser   = 'User' . $RandomID;
my $TestUserID = $UserObject->UserAdd(
    UserFirstname => $TestUser,
    UserLastname  => $TestUser,
    UserLogin     => $TestUser,
    UserPw        => $TestUser,
    UserEmail     => $TestUser . '@localunittest.com',
    ValidID       => 1,
    ChangeUserID  => 1,
);
$Self->True(
    $TestUserID,
    "UserAdd() $TestUser",
);

# create new customer user
my $TestCustomerUser   = 'CustomerUser' . $RandomID;
my $TestCustomerUserID = $CustomerUserObject->CustomerUserAdd(
    Source         => 'CustomerUser',
    UserFirstname  => $TestCustomerUser,
    UserLastname   => $TestCustomerUser,
    UserCustomerID => $TestCustomerUser,
    UserLogin      => $TestCustomerUser,
    UserEmail      => $TestCustomerUser . '@localunittest.com',
    ValidID        => 1,
    UserID         => 1,
);
$Self->True(
    $TestCustomerUserID,
    "CustomerUserAdd() $TestCustomerUser",
);

# create first test ticket
my $MasterTicketNumber = $TicketObject->TicketCreateNumber();
my $MasterTicketID     = $TicketObject->TicketCreate(
    TN           => $MasterTicketNumber,
    Title        => 'Master unit test ticket ' . $RandomID,
    Queue        => 'Raw',
    Lock         => 'unlock',
    Priority     => '3 normal',
    State        => 'new',
    CustomerNo   => $TestCustomerUser,
    CustomerUser => $TestCustomerUser . '@localunittest.com',
    OwnerID      => 1,
    UserID       => 1,
);
$Self->True(
    $MasterTicketID,
    "TicketCreate() Ticket ID $MasterTicketID",
);

# create article for test ticket
my $ArticleID = $TicketObject->ArticleCreate(
    TicketID       => $MasterTicketID,
    ArticleType    => 'email-external',
    SenderType     => 'agent',
    Subject        => 'Master Article',
    Body           => 'Unit test MasterTicket',
    ContentType    => 'text/plain; charset=ISO-8859-15',
    HistoryType    => 'EmailCustomer',
    HistoryComment => 'Unit test article',
    UserID         => 1,
);
$Self->True(
    $ArticleID,
    "ArticleCreate() Article ID $ArticleID",
);

# set test ticket as master ticket
my $Success = $DynamicFieldValueObject->ValueSet(
    FieldID  => $MasterSlaveDynamicFieldData->{ID},
    ObjectID => $MasterTicketID,
    Value    => [
        {
            ValueText => 'Master',
        },
    ],
    UserID => 1,
);
$Self->True(
    $Success,
    "ValueSet() Ticket ID $MasterTicketID DynamicField $MasterSlaveDynamicField updated as MasterTicket",
);

# create second test ticket
my $SlaveTicketNumber = $TicketObject->TicketCreateNumber();
my $SlaveTicketID     = $TicketObject->TicketCreate(
    TN           => $SlaveTicketNumber,
    Title        => 'Slave unit test ticket ' . $RandomID,
    Queue        => 'Raw',
    Lock         => 'unlock',
    Priority     => '3 normal',
    State        => 'new',
    CustomerID   => $TestCustomerUserID,
    CustomerUser => $TestCustomerUser . '@localunittest.com',
    OwnerID      => 1,
    UserID       => 1,
);
$Self->True(
    $SlaveTicketID,
    "TicketCreate() Ticket ID $SlaveTicketID",
);

# set test ticket as slave ticket
$Success = $DynamicFieldValueObject->ValueSet(
    FieldID  => $MasterSlaveDynamicFieldData->{ID},
    ObjectID => $SlaveTicketID,
    Value    => [
        {
            ValueText => "SlaveOf:$MasterTicketNumber",
        },
    ],
    UserID => 1,
);
$Self->True(
    $Success,
    "ValueSet() Ticket ID $SlaveTicketID DynamicField $MasterSlaveDynamicField updated as SlaveOf:$MasterTicketNumber",
);

# add parent-child link between master/slave tickets
$Success = $LinkObject->LinkAdd(
    SourceObject => 'Ticket',
    SourceKey    => $MasterTicketID,
    TargetObject => 'Ticket',
    TargetKey    => $SlaveTicketID,
    Type         => 'ParentChild',
    State        => 'Valid',
    UserID       => 1,
);
$Self->True(
    $Success,
    "LinkAdd() MasterSlave link established",
);

# ------------------------------------------------------------ #
# test event ArticleSend
# ------------------------------------------------------------ #

# create master ticket article and forward it
my $MasterNewSubject = $TicketObject->TicketSubjectBuild(
    TicketNumber => $MasterTicketNumber,
    Subject      => 'Master Article',
    Action       => 'Forward',
);
my $ForwardArticleID = $TicketObject->ArticleSend(
    TicketID       => $MasterTicketID,
    ArticleType    => 'email-external',
    SenderType     => 'agent',
    From           => 'Some Agent <email@example.com>',
    To             => 'Some Customer A <customer-a@example.com>',
    Subject        => $MasterNewSubject,
    Body           => 'Unit test forwarded article',
    Charset        => 'iso-8859-15',
    MimeType       => 'text/plain',
    HistoryType    => 'Forward',
    HistoryComment => 'Frowarded article',
    NoAgentNotify  => 0,
    UserID         => 1,
);
$Self->True(
    $Success,
    "ArticleSend() Forwarded MasterTicket Article ID $ForwardArticleID",
);

# get master ticket history
my @MasterHistoryLines = $TicketObject->HistoryGet(
    TicketID => $MasterTicketID,
    UserID   => 1,
);
my $MasterLastHistoryEntry = $MasterHistoryLines[ @MasterHistoryLines - 1 ];

# verify master ticket article is created
$Self->IsDeeply(
    $MasterLastHistoryEntry->{Name},
    'MasterTicketAction: ArticleSend',
    "MasterTicket ArticleSend event - ",
);

# get slave ticket history
my @SlaveHistoryLines = $TicketObject->HistoryGet(
    TicketID => $SlaveTicketID,
    UserID   => 1,
);
my $SlaveLastHistoryEntry = $SlaveHistoryLines[ @SlaveHistoryLines - 1 ];

# verify slave ticket article tried to send
$Self->IsDeeply(
    $SlaveLastHistoryEntry->{Name},
    'MasterTicket: no customer email found, send no master message to customer.',
    "SlaveTicket ArticleSend event - ",
);

# ------------------------------------------------------------ #
# test event ArticleCreate
# ------------------------------------------------------------ #

# create note article for master ticket
my $ArticleIDCreate = $TicketObject->ArticleCreate(
    TicketID       => $MasterTicketID,
    ArticleType    => 'note-internal',
    SenderType     => 'agent',
    Subject        => 'Note article',
    Body           => 'Unit test MasterTicket',
    ContentType    => 'text/plain; charset=ISO-8859-15',
    HistoryType    => 'AddNote',
    HistoryComment => 'Unit test article',
    UserID         => 1,
);
$Self->True(
    $ArticleIDCreate,
    "ArticleCreate() Note Article ID $ArticleIDCreate created for MasterTicket ID $MasterTicketID",
);

# get master ticket history
@MasterHistoryLines = $TicketObject->HistoryGet(
    TicketID => $MasterTicketID,
    UserID   => 1,
);
$MasterLastHistoryEntry = $MasterHistoryLines[ @MasterHistoryLines - 1 ];

# verify master ticket article is created
$Self->IsDeeply(
    $MasterLastHistoryEntry->{Name},
    'MasterTicketAction: ArticleCreate',
    "MasterTicket ArticleCreate event - ",
);

# get slave ticket history
@SlaveHistoryLines = $TicketObject->HistoryGet(
    TicketID => $SlaveTicketID,
    UserID   => 1,
);
$SlaveLastHistoryEntry = $SlaveHistoryLines[ @SlaveHistoryLines - 1 ];

# verify slave ticket article is created
$Self->IsDeeply(
    $SlaveLastHistoryEntry->{Name},
    'Added article based on master ticket.',
    "SlaveTicket ArticleCreate event - ",
);

# ------------------------------------------------------------ #
# test event TicketStateUpdate
# ------------------------------------------------------------ #

# change master ticket state to 'open'
$Success = $TicketObject->TicketStateSet(
    State    => 'open',
    TicketID => $MasterTicketID,
    UserID   => 1,
);
$Self->True(
    $Success,
    "TicketStateSet() MasterTicket state updated - 'open'",
);

# get master ticket history
@MasterHistoryLines = $TicketObject->HistoryGet(
    TicketID => $MasterTicketID,
    UserID   => 1,
);
$MasterLastHistoryEntry = $MasterHistoryLines[ @MasterHistoryLines - 1 ];

# verify master ticket state is updated
$Self->IsDeeply(
    $MasterLastHistoryEntry->{Name},
    'MasterTicketAction: TicketStateUpdate',
    "MasterTicket TicketStateUpdate event - ",
);

# verify slave ticket state is updated
my %SlaveTicketData = $TicketObject->TicketGet(
    TicketID => $SlaveTicketID,
    UserID   => 1,
);

$Self->IsDeeply(
    $SlaveTicketData{State},
    'open',
    "SlaveTicket state updated - 'open' - ",
);

# ------------------------------------------------------------ #
# test event TicketPendingTimeUpdate
# ------------------------------------------------------------ #

# change pending time for master ticket
$Success = $TicketObject->TicketPendingTimeSet(
    Year     => 0000,
    Month    => 00,
    Day      => 00,
    Hour     => 00,
    Minute   => 00,
    TicketID => $MasterTicketID,
    UserID   => 1,
);
$Self->True(
    $Success,
    "TicketPendingTimeSet() MasterTicket pending time updated",
);

# get master ticket history
@MasterHistoryLines = $TicketObject->HistoryGet(
    TicketID => $MasterTicketID,
    UserID   => 1,
);
$MasterLastHistoryEntry = $MasterHistoryLines[ @MasterHistoryLines - 1 ];

# verify master ticket pending time is updated
$Self->IsDeeply(
    $MasterLastHistoryEntry->{Name},
    'MasterTicketAction: TicketPendingTimeUpdate',
    "MasterTicket TicketPendingTimeUpdate event - ",
);

# get slave ticket history
@SlaveHistoryLines = $TicketObject->HistoryGet(
    TicketID => $SlaveTicketID,
    UserID   => 1,
);
$SlaveLastHistoryEntry = $SlaveHistoryLines[ @SlaveHistoryLines - 1 ];

# verify slave ticket pending time is updated
$Self->IsDeeply(
    $SlaveLastHistoryEntry->{Name},
    '%%00-00-00 00:00',
    "SlaveTicket pending time update - ",
);

# ------------------------------------------------------------ #
# test event TicketPriorityUpdate
# ------------------------------------------------------------ #

# change master ticket priority to '2 low'
$Success = $TicketObject->TicketPrioritySet(
    TicketID => $MasterTicketID,
    Priority => '2 low',
    UserID   => 1,
);
$Self->True(
    $Success,
    "TicketPrioritySet() MasterTicket priority updated - '2 low'",
);

# get master ticket history
@MasterHistoryLines = $TicketObject->HistoryGet(
    TicketID => $MasterTicketID,
    UserID   => 1,
);
$MasterLastHistoryEntry = $MasterHistoryLines[ @MasterHistoryLines - 1 ];

# verify master ticket priority is updated
$Self->IsDeeply(
    $MasterLastHistoryEntry->{Name},
    'MasterTicketAction: TicketPriorityUpdate',
    "MasterTicket TicketPriorityUpdate event - ",
);

# verify slave ticket priority is updated
%SlaveTicketData = $TicketObject->TicketGet(
    TicketID => $SlaveTicketID,
    UserID   => 1,
);
$Self->IsDeeply(
    $SlaveTicketData{Priority},
    '2 low',
    "SlaveTicket priority updated - '2 low' - ",
);

# ------------------------------------------------------------ #
# test event TicketOwnerUpdate
# ------------------------------------------------------------ #

# change master ticket owner
$Success = $TicketObject->TicketOwnerSet(
    TicketID => $MasterTicketID,
    NewUser  => $TestUser,
    UserID   => 1,
);
$Self->True(
    $Success,
    "TicketOwnerSet() MasterTicket owner updated - $TestUser",
);

# get master ticket history
@MasterHistoryLines = $TicketObject->HistoryGet(
    TicketID => $MasterTicketID,
    UserID   => 1,
);
$MasterLastHistoryEntry = $MasterHistoryLines[ @MasterHistoryLines - 1 ];

# verify master ticket owner is updated
$Self->IsDeeply(
    $MasterLastHistoryEntry->{Name},
    'MasterTicketAction: TicketOwnerUpdate',
    "MasterTicket TicketOwnerUpdate event - ",
);

# verify slave ticket owner is updated
%SlaveTicketData = $TicketObject->TicketGet(
    TicketID => $SlaveTicketID,
    UserID   => 1,
);
$Self->IsDeeply(
    $SlaveTicketData{Owner},
    $TestUser,
    "SlaveTicket owner updated - ",
);

# ------------------------------------------------------------ #
# test event TicketResponsibleUpdate
# ------------------------------------------------------------ #

# set new responsible user for master ticket
$Success = $TicketObject->TicketResponsibleSet(
    TicketID => $MasterTicketID,
    NewUser  => $TestUser,
    UserID   => 1,
);
$Self->True(
    $Success,
    "TicketResponsibleSet() MasterTicket responsible updated - $TestUser",
);

# get master ticket history
@MasterHistoryLines = $TicketObject->HistoryGet(
    TicketID => $MasterTicketID,
    UserID   => 1,
);
$MasterLastHistoryEntry = $MasterHistoryLines[ @MasterHistoryLines - 1 ];

# verify master ticket responsible user is updated
$Self->IsDeeply(
    $MasterLastHistoryEntry->{Name},
    'MasterTicketAction: TicketResponsibleUpdate',
    "MasterTicket TicketResponsibleUpdate event - ",
);

# verify slave ticket owner is updated
%SlaveTicketData = $TicketObject->TicketGet(
    TicketID => $SlaveTicketID,
    UserID   => 1,
);
$Self->IsDeeply(
    $SlaveTicketData{Responsible},
    $TestUser,
    "SlaveTicket responsible updated - ",
);

# ------------------------------------------------------------ #
# test event TicketLockUpdate
# ------------------------------------------------------------ #

# lock master ticket
$Success = $TicketObject->TicketLockSet(
    Lock     => 'lock',
    TicketID => $MasterTicketID,
    UserID   => 1,
);
$Self->True(
    $Success,
    "TicketLockSet() MasterTicket is locked",
);

# get master ticket history
@MasterHistoryLines = $TicketObject->HistoryGet(
    TicketID => $MasterTicketID,
    UserID   => 1,
);
$MasterLastHistoryEntry = $MasterHistoryLines[ @MasterHistoryLines - 1 ];

# verify master ticket is locked
$Self->IsDeeply(
    $MasterLastHistoryEntry->{Name},
    'MasterTicketAction: TicketLockUpdate',
    "MasterTicket TicketLockUpdate event - ",
);

# verify slave ticket is locked
%SlaveTicketData = $TicketObject->TicketGet(
    TicketID => $SlaveTicketID,
    UserID   => 1,
);
$Self->IsDeeply(
    $SlaveTicketData{Lock},
    'lock',
    "SlaveTicket lock updated - ",
);

# cleanup is done by RestoreDatabase

1;
