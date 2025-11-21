function Set-CIPPCloudManaged(
    [string]$TenantFilter,
    [string]$Id,
    [string]$DisplayName,
    [ValidateSet('User', 'Group', 'Contact')]
    [string]$Type,
    [bool]$IsCloudManaged,
    [string]$APIName = 'Set Cloud Managed',
    $Headers
) {
    try {
        $statusText = if ($IsCloudManaged -eq $true) { 'cloud-managed' } else { 'on-premises managed' }

        $URI = switch ($Type) {
            'User' { "https://graph.microsoft.com/beta/users/$Id/onPremisesSyncBehavior" }
            'Group' { "https://graph.microsoft.com/beta/groups/$Id/onPremisesSyncBehavior" }
            'Contact' { "https://graph.microsoft.com/beta/contacts/$Id/onPremisesSyncBehavior" }
        }

        $Body = @{
            isCloudManaged = $IsCloudManaged
        } | ConvertTo-Json -Depth 10

        $null = New-GraphPOSTRequest -uri $URI -type PATCH -tenantid $TenantFilter -body $Body -AsApp $true
        $Message = "Successfully set $Type $DisplayName ($Id) source of authority to $statusText"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Info'
        return $Message
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Failed to set $Type $DisplayName ($Id) source of authority to ${statusText}: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Error' -LogData $ErrorMessage
        throw $Message
    }
}
