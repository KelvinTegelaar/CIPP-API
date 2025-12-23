function Invoke-CippTestZTNA21812 {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Tenant
    )

    $TestId = 'ZTNA21812'

    try {
        $AllGlobalAdmins = Get-CippDbRoleMembers -TenantFilter $Tenant -RoleTemplateId '62e90394-69f5-4237-9190-012177145e10'
        
        $GlobalAdmins = @($AllGlobalAdmins | Where-Object { $_.'@odata.type' -in @('#microsoft.graph.user', '#microsoft.graph.servicePrincipal') })

        $Passed = $GlobalAdmins.Count -le 5

        if ($Passed) {
            $ResultMarkdown = "Maximum number of Global Administrators doesn't exceed five users/service principals.`n`n"
        } else {
            $ResultMarkdown = "Maximum number of Global Administrators exceeds five users/service principals.`n`n"
        }

        if ($GlobalAdmins.Count -gt 0) {
            $ResultMarkdown += "## Global Administrators`n`n"
            $ResultMarkdown += "### Total number of Global Administrators: $($GlobalAdmins.Count)`n`n"
            $ResultMarkdown += "| Display Name | Object Type | User Principal Name |`n"
            $ResultMarkdown += "| :----------- | :---------- | :------------------ |`n"

            foreach ($GlobalAdmin in $GlobalAdmins) {
                $DisplayName = $GlobalAdmin.displayName
                $ObjectType = switch ($GlobalAdmin.'@odata.type') {
                    '#microsoft.graph.user' { 'User' }
                    '#microsoft.graph.servicePrincipal' { 'Service Principal' }
                    default { 'Unknown' }
                }
                $UserPrincipalName = if ($GlobalAdmin.userPrincipalName) { $GlobalAdmin.userPrincipalName } else { 'N/A' }
                
                $PortalLink = switch ($ObjectType) {
                    'User' { "https://entra.microsoft.com/#view/Microsoft_AAD_UsersAndTenants/UserProfileMenuBlade/~/AdministrativeRole/userId/$($GlobalAdmin.id)" }
                    'Service Principal' { "https://entra.microsoft.com/#view/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/~/Overview/appId/$($GlobalAdmin.id)" }
                    default { 'https://entra.microsoft.com' }
                }

                $ResultMarkdown += "| [$DisplayName]($PortalLink) | $ObjectType | $UserPrincipalName |`n"
            }
        }

        return @{
            TestId         = $TestId
            Status         = if ($Passed) { 'Passed' } else { 'Failed' }
            ResultMarkdown = $ResultMarkdown
        }

    } catch {
        return @{
            TestId         = $TestId
            Status         = 'Failed'
            ResultMarkdown = "Error running test: $($_.Exception.Message)"
        }
    }
}
