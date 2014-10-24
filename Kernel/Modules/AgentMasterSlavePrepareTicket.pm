# --
# Kernel/Modules/AgentMasterSlavePrepareTicket.pm - to prepare master/slave pull downs
# Copyright (C) 2001-2014 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::Modules::AgentMasterSlavePrepareTicket;

use strict;
use warnings;

use Kernel::Language;
use Kernel::System::DynamicField;
use Data::Compare;

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    # check needed Objects
    for my $Needed (
        qw(ParamObject DBObject LayoutObject LogObject ConfigObject TicketObject UserObject UserID)
        )
    {
        if ( !$Self->{$Needed} ) {
            $Self->{LayoutObject}->FatalError( Message => "Got no $Needed!" );
        }
    }
    $Self->{UserLanguage} = $Self->{LayoutObject}->{UserLanguage}
        || $Self->{ConfigObject}->Get('DefaultLanguage');
    $Self->{LanguageObject}
        = Kernel::Language->new(
        %Param,
        UserLanguage => $Self->{UserLanguage}
        );

    $Self->{DynamicFieldObject} = Kernel::System::DynamicField->new(%Param);

    return $Self;
}

sub PreRun {
    my ( $Self, %Param ) = @_;

    # do only use this in phone and email ticket
    return if ( $Self->{Action} !~ /^AgentTicket(Email|Phone)$/ );

    # get master/slave dynamic field
    my $MasterSlaveDynamicField = $Self->{ConfigObject}->Get('MasterSlave::DynamicField') || '';

    # return if no config option is used
    return if !$MasterSlaveDynamicField;

    # get dynamic field config
    my $DynamicField = $Self->{DynamicFieldObject}->DynamicFieldGet(
        Name => $MasterSlaveDynamicField,
    );

    # return if no dynamic field config is retrieved
    return if !$DynamicField;

    # find all current open master slave tickets
    my @TicketIDs = $Self->{TicketObject}->TicketSearch(

        # result (required)
        Result => 'ARRAY',

        # master slave dynamic field
        'DynamicField_' . $MasterSlaveDynamicField => {
            Equals => 'Master',
        },
        StateType => 'Open',

        # result limit
        Limit      => 60,
        UserID     => $Self->{UserID},
        Permission => 'ro',
    );

    # set dynamic field as shown
    $Self->{ConfigObject}->{"Ticket::Frontend::$Self->{Action}"}->{DynamicField}
        ->{$MasterSlaveDynamicField} = 1;

    # check if PossibleValues has changed
    my %ValuesOld = %{ $DynamicField->{Config}->{PossibleValues} };
    # /check if PossibleValues has changed

    # set dynamic field possible values
    $DynamicField->{Config}->{PossibleValues} = {
        Master => $Self->{LanguageObject}->Get('New Master Ticket'),
    };
    $DynamicField->{Config}->{DefaultValue} = '';
    $DynamicField->{Config}->{PossibleNone} = 1;

    TICKET:
    for my $TicketID (@TicketIDs) {
        my %CurrentTicket = $Self->{TicketObject}->TicketGet(
            TicketID      => $TicketID,
            DynamicFields => 1,
        );

        next TICKET if !%CurrentTicket;

        # set dynamic field possible values
        $DynamicField->{Config}->{PossibleValues}{
            "SlaveOf:$CurrentTicket{TicketNumber}"
            }
            =
            $Self->{LanguageObject}->Get('Slave of Ticket#')
            . "$CurrentTicket{TicketNumber}: $CurrentTicket{Title}";
    }

    # check if PossibleValues has changed, only update (and delete while cache) if needed
    my $Diff = Compare( \%ValuesOld , $DynamicField->{Config}->{PossibleValues} );
    return if $Diff;
    # /check if PossibleValues has changed, only update (and delete while cache) if needed

    # set new dynamic field values
    my $SuccessTicketField = $Self->{DynamicFieldObject}->DynamicFieldUpdate(
        %{$DynamicField},
        Reorder => 0,
        ValidID => 1,
        UserID  => $Self->{UserID},
    );

    return;
}

1;
