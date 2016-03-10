# --
# Copyright (C) 2001-2016 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::DynamicField::Driver::MasterSlave;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(:all);

use base qw(Kernel::System::DynamicField::Driver::BaseSelect);

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::Output::HTML::Layout',
    'Kernel::System::DynamicFieldValue',
    'Kernel::System::LinkObject',
    'Kernel::System::Log',
    'Kernel::System::Main',
    'Kernel::System::Ticket',
);

=head1 NAME

Kernel::System::DynamicField::Driver::MasterSlave

=head1 SYNOPSIS

DynamicFields MasterSlave Driver delegate

=head1 PUBLIC INTERFACE

This module implements the public interface of L<Kernel::System::DynamicField::Backend>.
Please look there for a detailed reference of the functions.

=over 4

=item new()

usually, you want to create an instance of this
by using Kernel::System::DynamicField::Backend->new();

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    # set field behaviors
    $Self->{Behaviors} = {
        'IsACLReducible'               => 0,
        'IsNotificationEventCondition' => 1,
        'IsSortable'                   => 1,
        'IsFiltrable'                  => 1,
        'IsStatsCondition'             => 1,
        'IsCustomerInterfaceCapable'   => 1,
    };

    # get the Dynamic Field Backend custom extensions
    my $DynamicFieldDriverExtensions
        = $Kernel::OM->Get('Kernel::Config')->Get('DynamicFields::Extension::Driver::MasterSlave');

    EXTENSION:
    for my $ExtensionKey ( sort keys %{$DynamicFieldDriverExtensions} ) {

        # skip invalid extensions
        next EXTENSION if !IsHashRefWithData( $DynamicFieldDriverExtensions->{$ExtensionKey} );

        # create a extension config shortcut
        my $Extension = $DynamicFieldDriverExtensions->{$ExtensionKey};

        # check if extension has a new module
        if ( $Extension->{Module} ) {

            # check if module can be loaded
            if (
                !$Kernel::OM->Get('Kernel::System::Main')->RequireBaseClass( $Extension->{Module} )
                )
            {
                die "Can't load dynamic fields backend module"
                    . " $Extension->{Module}! $@";
            }
        }

        # check if extension contains more behaviors
        if ( IsHashRefWithData( $Extension->{Behaviors} ) ) {

            %{ $Self->{Behaviors} } = (
                %{ $Self->{Behaviors} },
                %{ $Extension->{Behaviors} }
            );
        }
    }

    return $Self;
}

sub ValueSet {
    my ( $Self, %Param ) = @_;

    my $Success = $Self->_HandleLinks(
        FieldName  => $Param{DynamicFieldConfig}->{Name},
        FieldValue => $Param{Value},
        TicketID   => $Param{ObjectID},
        UserID     => $Param{UserID},
    );

    if ( !$Success ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "There was an error handling the links for master/slave, value could not be set",
        );

        return;
    }

    my $Value = $Param{Value} !~ /^(?:UnsetMaster|UnsetSlave)$/ ? $Param{Value} : '';

    $Success = $Kernel::OM->Get('Kernel::System::DynamicFieldValue')->ValueSet(
        FieldID  => $Param{DynamicFieldConfig}->{ID},
        ObjectID => $Param{ObjectID},
        Value    => [
            {
                ValueText => $Value,
            },
        ],
        UserID => $Param{UserID},
    );

    return $Success;
}

sub EditFieldValueValidate {
    my ( $Self, %Param ) = @_;

    # get the field value from the http request
    my $Value = $Self->EditFieldValueGet(
        DynamicFieldConfig => $Param{DynamicFieldConfig},
        ParamObject        => $Param{ParamObject},

        # not necessary for this Driver but place it for consistency reasons
        ReturnValueStructure => 1,
    );

    my $ServerError;
    my $ErrorMessage;

    # perform necessary validations
    if ( $Param{Mandatory} && !$Value ) {
        return {
            ServerError => 1,
        };
    }
    else {

        my $PossibleValues;

        # use PossibleValuesFilter if sent
        if ( defined $Param{PossibleValuesFilter} ) {
            $PossibleValues = $Param{PossibleValuesFilter}
        }
        else {

            # get possible values list
            $PossibleValues = $Self->PossibleValuesGet(
                %Param,
            );
        }

        # validate if value is in possible values list (but let pass empty values)
        if ( $Value && !$PossibleValues->{$Value} ) {
            $ServerError  = 1;
            $ErrorMessage = 'The field content is invalid';
        }
    }

    # create resulting structure
    my $Result = {
        ServerError  => $ServerError,
        ErrorMessage => $ErrorMessage,
    };

    return $Result;
}

sub PossibleValuesGet {
    my ( $Self, %Param ) = @_;

    # to store the possible values
    my %PossibleValues = (
        '' => '-',
    );

    # get needed objects
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    # find all current open master slave tickets
    my @TicketIDs = $TicketObject->TicketSearch(
        Result => 'ARRAY',

        # master slave dynamic field
        'DynamicField_' . $Param{DynamicFieldConfig}->{Name} => {
            Equals => 'Master',
        },

        StateType  => 'Open',
        Limit      => 60,
        UserID     => $LayoutObject->{UserID},
        Permission => 'ro',
    );

    # set dynamic field possible values
    $PossibleValues{Master} = $LayoutObject->{LanguageObject}->Translate('New Master Ticket');

    TICKET:
    for my $TicketID (@TicketIDs) {
        my %CurrentTicket = $TicketObject->TicketGet(
            TicketID      => $TicketID,
            DynamicFields => 1,
        );

        next TICKET if !%CurrentTicket;

        # set dynamic field possible values
        $PossibleValues{"SlaveOf:$CurrentTicket{TicketNumber}"}
            = $LayoutObject->{LanguageObject}->Translate('Slave of Ticket#')
            . "$CurrentTicket{TicketNumber}: $CurrentTicket{Title}";
    }

    # return the possible values hash as a reference
    return \%PossibleValues;
}

sub _HandleLinks {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Needed (qw(FieldName FieldValue TicketID UserID)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!",
            );
            return;
        }
    }

    # get ticket object
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');

    my $FieldName = $Param{FieldName};

    my %Ticket = $Param{Ticket}
        ? %{ $Param{Ticket} }
        : $TicketObject->TicketGet(
        TicketID      => $Param{TicketID},
        DynamicFields => 1
        );

    my $OldValue = $Ticket{ 'DynamicField_' . $FieldName };

    # get config object
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    # get master slave config
    my $MasterSlaveKeepParentChildAfterUnset  = $ConfigObject->Get('MasterSlave::KeepParentChildAfterUnset')  || 0;
    my $MasterSlaveFollowUpdatedMaster        = $ConfigObject->Get('MasterSlave::FollowUpdatedMaster')        || 0;
    my $MasterSlaveKeepParentChildAfterUpdate = $ConfigObject->Get('MasterSlave::KeepParentChildAfterUpdate') || 0;

    my $NewValue = $Param{FieldValue};

    # get link object
    my $LinkObject = $Kernel::OM->Get('Kernel::System::LinkObject');

    # set a new master ticket
    # check if it is already a master ticket
    if (
        $NewValue eq 'Master'
        && ( !$OldValue || $OldValue ne $NewValue )
        )
    {

        # check if it was a slave ticket before and if we have to delete
        # the old parent child link (MasterSlaveKeepParentChildAfterUnset)
        if (
            $OldValue
            && $OldValue =~ /^SlaveOf:(.*?)$/
            && !$MasterSlaveKeepParentChildAfterUnset
            )
        {
            my $SourceKey = $TicketObject->TicketIDLookup(
                TicketNumber => $1,
                UserID       => $Param{UserID},
            );

            $LinkObject->LinkDelete(
                Object1 => 'Ticket',
                Key1    => $SourceKey,
                Object2 => 'Ticket',
                Key2    => $Param{TicketID},
                Type    => 'ParentChild',
                UserID  => $Param{UserID},
            );
        }
    }

    # set a new slave ticket
    # check if it's already the slave of the wished master ticket
    elsif (
        $NewValue =~ /^SlaveOf:(.*?)$/
        && ( !$OldValue || $OldValue ne $NewValue )
        )
    {
        my $SourceKey = $TicketObject->TicketIDLookup(
            TicketNumber => $1,
            UserID       => $Param{UserID},
        );

        $LinkObject->LinkAdd(
            SourceObject => 'Ticket',
            SourceKey    => $SourceKey,
            TargetObject => 'Ticket',
            TargetKey    => $Param{TicketID},
            Type         => 'ParentChild',
            State        => 'Valid',
            UserID       => $Param{UserID},
        );

        my %Links = $LinkObject->LinkKeyList(
            Object1   => 'Ticket',
            Key1      => $Param{TicketID},
            Object2   => 'Ticket',
            State     => 'Valid',
            Type      => 'ParentChild',      # (optional)
            Direction => 'Target',           # (optional) default Both (Source|Target|Both)
            UserID    => $Param{UserID},
        );

        my @SlaveTicketIDs;

        LINKEDTICKETID:
        for my $LinkedTicketID ( sort keys %Links ) {
            next LINKEDTICKETID if !$Links{$LinkedTicketID};

            # just take ticket with slave attributes for action
            my %LinkedTicket = $TicketObject->TicketGet(
                TicketID      => $LinkedTicketID,
                DynamicFields => 1,
            );

            my $LinkedTicketValue = $Ticket{ 'DynamicField_' . $FieldName };

            next LINKEDTICKETID if !$LinkedTicketValue;
            next LINKEDTICKETID if $LinkedTicketValue !~ /^SlaveOf:(.*?)$/;

            # remember linked ticket id
            push @SlaveTicketIDs, $LinkedTicketID;
        }

        if ( $OldValue && $OldValue eq 'Master' ) {

            if ( $MasterSlaveFollowUpdatedMaster && @SlaveTicketIDs ) {
                for my $LinkedTicketID (@SlaveTicketIDs) {
                    $LinkObject->LinkAdd(
                        SourceObject => 'Ticket',
                        SourceKey    => $SourceKey,
                        TargetObject => 'Ticket',
                        TargetKey    => $LinkedTicketID,
                        Type         => 'ParentChild',
                        State        => 'Valid',
                        UserID       => $Param{UserID},
                    );
                }
            }

            if ( !$MasterSlaveKeepParentChildAfterUnset ) {
                for my $LinkedTicketID (@SlaveTicketIDs) {
                    $LinkObject->LinkDelete(
                        Object1 => 'Ticket',
                        Key1    => $Param{TicketID},
                        Object2 => 'Ticket',
                        Key2    => $LinkedTicketID,
                        Type    => 'ParentChild',
                        UserID  => $Param{UserID},
                    );
                }
            }
        }
        elsif (
            $OldValue
            && $OldValue =~ /^SlaveOf:(.*?)$/
            && !$MasterSlaveKeepParentChildAfterUpdate
            )
        {
            my $SourceKey = $TicketObject->TicketIDLookup(
                TicketNumber => $1,
                UserID       => $Param{UserID},
            );

            $LinkObject->LinkDelete(
                Object1 => 'Ticket',
                Key1    => $SourceKey,
                Object2 => 'Ticket',
                Key2    => $Param{TicketID},
                Type    => 'ParentChild',
                UserID  => $Param{UserID},
            );
        }
    }
    elsif ( $NewValue =~ /^(?:UnsetMaster|UnsetSlave)$/ && $OldValue ) {

        if ( $NewValue eq 'UnsetMaster' && !$MasterSlaveKeepParentChildAfterUnset ) {
            my %Links = $LinkObject->LinkKeyList(
                Object1   => 'Ticket',
                Key1      => $Param{TicketID},
                Object2   => 'Ticket',
                State     => 'Valid',
                Type      => 'ParentChild',      # (optional)
                Direction => 'Target',           # (optional) default Both (Source|Target|Both)
                UserID    => $Param{UserID},
            );

            my @SlaveTicketIDs;

            LINKEDTICKETID:
            for my $LinkedTicketID ( sort keys %Links ) {
                next LINKEDTICKETID if !$Links{$LinkedTicketID};

                # just take ticket with slave attributes for action
                my %LinkedTicket = $TicketObject->TicketGet(
                    TicketID      => $LinkedTicketID,
                    DynamicFields => 1,
                );

                my $LinkedTicketValue = $Ticket{ 'DynamicField_' . $FieldName };
                next LINKEDTICKETID if !$LinkedTicketValue;
                next LINKEDTICKETID if $LinkedTicketValue !~ /^SlaveOf:(.*?)$/;

                # remember ticket id
                push @SlaveTicketIDs, $LinkedTicketID;
            }

            for my $LinkedTicketID (@SlaveTicketIDs) {
                $LinkObject->LinkDelete(
                    Object1 => 'Ticket',
                    Key1    => $Param{TicketID},
                    Object2 => 'Ticket',
                    Key2    => $LinkedTicketID,
                    Type    => 'ParentChild',
                    UserID  => $Param{UserID},
                );
            }
        }
        elsif (
            $NewValue eq 'UnsetSlave'
            && !$MasterSlaveKeepParentChildAfterUnset
            && $OldValue =~ /^SlaveOf:(.*?)$/
            )
        {
            my $SourceKey = $TicketObject->TicketIDLookup(
                TicketNumber => $1,
                UserID       => $Param{UserID},
            );

            $LinkObject->LinkDelete(
                Object1 => 'Ticket',
                Key1    => $SourceKey,
                Object2 => 'Ticket',
                Key2    => $Param{TicketID},
                Type    => 'ParentChild',
                UserID  => $Param{UserID},
            );
        }
    }

    return 1;
}

1;

=back

=head1 TERMS AND CONDITIONS

This software is part of the OTRS project (L<http://otrs.org/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (AGPL). If you
did not receive this file, see L<http://www.gnu.org/licenses/agpl.txt>.

=cut
