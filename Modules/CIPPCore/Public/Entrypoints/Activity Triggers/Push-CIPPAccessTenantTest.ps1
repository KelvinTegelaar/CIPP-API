function Push-CIPPAccessTenantTest {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    Param($Item)

    Test-CIPPAccessTenant -Tenant $Item.customerId -ExecutingUser 'CIPP'
}
