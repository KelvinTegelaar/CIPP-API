function Invoke-ListExoRequest {
    param($Request, $TriggerMetadata)

    try {
        $AllowedVerbs = @(
            'Get'
            'Search'
        )

        $Cmdlet = $Request.Body.Cmdlet
        $cmdParams = if ($Request.Body.cmdParams) { $Request.Body.cmdParams } else { [PSCustomObject]@{} }
        $Verb = ($Cmdlet -split '-')[0]

        $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList
        $TenantFilter = $Request.Body.TenantFilter
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

            if ($Request.Body.Select) {
                $ExoParams.Select = $Request.Body.Select
            }

            if ($Request.Body.UseSystemMailbox -eq $true) {
                $ExoParams.useSystemMailbox = $true
            }

            if ($Request.Body.Anchor) {
                $ExoParams.Anchor = $Request.Body.Anchor
            }

            if ($Request.Body.Compliance -eq $true) {
                $ExoParams.Compliance = $true
            }

            if ($Request.Body.AsApp -eq $true) {
                $ExoParams.AsApp = $true
            }

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
