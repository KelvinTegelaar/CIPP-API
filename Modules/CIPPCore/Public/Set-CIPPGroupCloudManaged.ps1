function Set-CIPPGroupCloudManaged(
    [string]$TenantFilter,
    [string]$Id,
    [string]$DisplayName,
    [bool]$IsCloudManaged,
    [string]$APIName = 'Set Group Cloud Managed',
    $Headers
) {
    try {
        $statusText = if ($IsCloudManaged -eq $true) { 'cloud-managed' } else { 'on-premises managed' }


        $Body = @{
            isCloudManaged = $IsCloudManaged
        } | ConvertTo-Json -Depth 10

        $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/groups/$Id/onPremisesSyncBehavior" -type PATCH -tenantid $TenantFilter -body $Body -AsApp $true

        $Message = "Successfully set group $DisplayName ($Id) source of authority to $statusText"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Info'
        return $Message
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Failed to set group $DisplayName ($Id) source of authority to ${statusText}: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Error' -LogData $ErrorMessage
        throw $Message
    }
}
