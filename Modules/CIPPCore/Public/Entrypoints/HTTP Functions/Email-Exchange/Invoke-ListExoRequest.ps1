function Invoke-ListExoRequest {
    param($Request, $TriggerMetadata)

    try {
        $AllowedVerbs = @(
            'Get'
            'Search'
        )

        Write-Information ($Request.Query | ConvertTo-Json)
        $Cmdlet = $Request.Query.Cmdlet
        $cmdParams = if ($Request.Body) { $Request.Body } else { [PSCustomObject]@{} }
        $Verb = ($Cmdlet -split '-')[0]

        $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList
        $TenantFilter = $Request.Query.TenantFilter
        $Tenants = Get-Tenants -IncludeErrors
        $Tenant = $Tenants | Where-Object { $_.defaultDomainName -eq $TenantFilter -or $_.customerId -eq $TenantFilter }
        if ($Tenant.customerId -in $AllowedTenants -or $AllowedTenants -eq 'AllTenants') {
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
        } else {
            $Body = [pscustomobject]@{
                Results = "Invalid tenant: $TenantFilter"
            }
        }
    } catch {
        Write-Information "ExoRequest Error: $($_.Exception.Message)"
    }
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = ConvertTo-Json -InputObject $Body -Compress
        })
}
