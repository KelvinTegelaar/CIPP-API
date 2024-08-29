function Invoke-ListExoRequest {
    param($Request, $TriggerMetadata)

    $AllowedVerbs = @(
        'Get'
        'Search'
    )

    $Cmdlet = $Request.Query.Cmdlet
    $cmdParams = if ($Request.Body) { $Request.Body } else { [PSCustomObject]@{} }
    $Verb = ($Cmdlet -split '-')[0]

    $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList
    $TenantFilter = $Request.Query.TenantFilter
    $Tenants = Get-Tenants -IncludeErrors
    $Tenant = $Tenants | Where-Object { $_.defaultDomainName -eq $TenantFilter -or $_.customerId -eq $TenantFilter }
    if ($Tenant.customerId -in $AllowedTenants) {
        if ($AllowedVerbs -notcontains $Verb) {
            $Body = [pscustomobject]@{
                Results = "Invalid cmdlet: $Cmdlet"
            }
            Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = $Body
                })
            return
        }
        $ExoParams = @{
            Cmdlet    = $Cmdlet
            cmdParams = $cmdParams
            tenantid  = $TenantFilter
        }

        if ($Request.Query.Select) {
            $ExoParams.Select = $Request.Query.Select
        }

        if ($Request.Query.UseSystemMailbox) {
            $ExoParams.useSystemMailbox = $true
        }

        if ($Request.Query.Anchor) {
            $ExoParams.Anchor = $Request.Query.Anchor
        }

        if ($Request.Query.Compliance) {
            $ExoParams.Compliance = $true
        }

        if ($Request.Query.AsApp) {
            $ExoParams.AsApp = $true
        }

        Write-Information ($ExoParams | ConvertTo-Json)
        $Results = New-ExoRequest @ExoParams
        $Body = [pscustomobject]@{
            Results = $Results
        }
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = ConvertTo-Json -InputObject $Body -Compress
            })
    }
}
