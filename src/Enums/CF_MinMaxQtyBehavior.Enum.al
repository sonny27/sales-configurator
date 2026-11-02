namespace CloudFactory.SalesConfigurator;

enum 91002 CF_MinMaxQtyBehavior
{
    Extensible = false;

    value(0; NotEnabled)
    {
        Caption = 'Not Enabled';
    }
    value(1; MinAndMax)
    {
        Caption = 'Check Both Minimum and Maximum';
    }
    value(2; MinOnly)
    {
        Caption = 'Check Minimum Only';
    }
    value(3; MaxOnly)
    {
        Caption = 'Check Maximum Only';
    }
}
