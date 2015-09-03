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

use Kernel::System::VariableCheck qw(:all);

# get needed objects
my $HelperObject              = $Kernel::OM->Get('Kernel::System::UnitTest::Helper');
my $DynamicFieldObject        = $Kernel::OM->Get('Kernel::System::DynamicField');
my $DynamicFieldBackendObject = $Kernel::OM->Get('Kernel::System::DynamicField::Backend');
my $ParamObject               = $Kernel::OM->Get('Kernel::System::Web::Request');
my $LayoutObject              = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
my $ConfigObject              = $Kernel::OM->Get('Kernel::Config');

# ------------------------------------------------------------ #
# make preparations
# ------------------------------------------------------------ #

# get master/slave dynamic field data
my $MasterSlaveDynamicField     = $ConfigObject->Get('MasterSlave::DynamicField');
my $MasterSlaveDynamicFieldData = $DynamicFieldObject->DynamicFieldGet(
    Name => $MasterSlaveDynamicField,
);

# get master/slave dynamic field possible values
my $PossibleValues = $DynamicFieldBackendObject->PossibleValuesGet(
    DynamicFieldConfig => $MasterSlaveDynamicFieldData,
);

# define tests
my @Tests = (
    {
        Name   => 'MasterSlave',
        Config => {
            DynamicFieldConfig   => $MasterSlaveDynamicFieldData,
            PossibleValuesFilter => $PossibleValues,
            LayoutObject         => $LayoutObject,
            ParamObject          => $ParamObject,
        },
        ExpectedResults => {
            Field =>
                '<select class="DynamicFieldText Modernize" id="DynamicField_MasterSlave" name="DynamicField_MasterSlave" size="1">
  <option value="" selected="selected">-</option>
  <option value="Master">New Master Ticket</option>
</select>
',
            Label => '<label id="LabelDynamicField_MasterSlave" for="DynamicField_MasterSlave">
Master Ticket:
</label>
'
        },
    },
);

# ------------------------------------------------------------ #
# execute tests
# ------------------------------------------------------------ #

for my $Test (@Tests) {

    my $FieldHTML = $DynamicFieldBackendObject->EditFieldRender( %{ $Test->{Config} } );

    # heredocs always have the newline, even if it is not expected
    if ( $FieldHTML->{Field} !~ m{\n$} ) {
        chomp $Test->{ExpectedResults}->{Field};
    }

    $Self->IsDeeply(
        $FieldHTML,
        $Test->{ExpectedResults},
        "$Test->{Name} | EditFieldRender()",
    );

}

1;
