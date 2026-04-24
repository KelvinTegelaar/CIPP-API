Function Invoke-ListUserDevices {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    $UserID = $Request.Query.UserID

    function Get-EPMID {
        param(
            $deviceID,
            $EPMDevices
        )
        try {
            return ($EPMDevices | Where-Object { $_.azureADDeviceId -eq $deviceID }).id
        } catch {
            return $null
        }
    }
    try {
        $EPMDevices = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$UserID/managedDevices" -Tenantid $TenantFilter
        $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$UserID/ownedDevices?`$top=999" -Tenantid $TenantFilter | Select-Object @{ Name = 'ID'; Expression = { $_.'id' } },
        @{ Name = 'accountEnabled'; Expression = { $_.'accountEnabled' } },
        @{ Name = 'approximateLastSignInDateTime'; Expression = { $_.'approximateLastSignInDateTime' | Out-String } },
        @{ Name = 'createdDateTime'; Expression = { $_.'createdDateTime' | Out-String } },
        @{ Name = 'deviceOwnership'; Expression = { $_.'deviceOwnership' } },
        @{ Name = 'displayName'; Expression = { $_.'displayName' } },
        @{ Name = 'enrollmentType'; Expression = { $_.'enrollmentType' } },
        @{ Name = 'isCompliant'; Expression = { $_.'isCompliant' } },
        @{ Name = 'managementType'; Expression = { $_.'managementType' } },
        @{ Name = 'manufacturer'; Expression = { $_.'manufacturer' } },
        @{ Name = 'model'; Expression = { $_.'model' } },
        @{ Name = 'operatingSystem'; Expression = { $_.'operatingSystem' } },
        @{ Name = 'onPremisesSyncEnabled'; Expression = { $(if ([string]::IsNullOrEmpty($_.'onPremisesSyncEnabled')) { $false }else { $true }) } },
        @{ Name = 'operatingSystemVersion'; Expression = { $_.'operatingSystemVersion' } },
        @{ Name = 'trustType'; Expression = { $_.'trustType' } },
        @{ Name = 'EPMID'; Expression = { $(Get-EPMID -deviceID $_.'deviceId' -EPMDevices $EPMDevices) } }
    } catch {
        $GraphRequest = @()
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($GraphRequest)
        })

}
