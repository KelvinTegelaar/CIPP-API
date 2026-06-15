function Push-CIPPAccessTenantTest {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    Param($Item)

    Test-CIPPAccessTenant -Tenant $Item.customerId -Headers 'CIPP'
}
