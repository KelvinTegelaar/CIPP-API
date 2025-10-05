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
            if ($Request.Body.AvailableCmdlets) {
                $ExoRequest = @{
                    TenantID         = $TenantFilter
                    AvailableCmdlets = $true
                }
                if ($Request.Body.AsApp -eq $true) {
                    $ExoRequest.AsApp = $true
                }
                if ($Request.Body.Compliance -eq $true) {
                    $ExoRequest.Compliance = $true
                }
                $Results = New-ExoRequest @ExoRequest
                $Body = [PSCustomObject]@{
                    Results  = $Results | Select-Object @{ Name = 'Cmdlet'; Expression = { $_ } }
                    Metadata = @{
                        Count = ($Results | Measure-Object).Count
                    }
                }
            } else {
                if ($AllowedVerbs -notcontains $Verb) {
                    $Body = [pscustomobject]@{
                        Results = "Invalid cmdlet: $Cmdlet"
                    }
                    return ([HttpResponseContext]@{
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

                try {
                    $Results = New-ExoRequest @ExoParams
                    $Body = [pscustomobject]@{
                        Results = $Results
                    }
                } catch {
                    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                    $Body = [pscustomobject]@{
                        Results = @(@{ Error = $ErrorMessage })
                    }
                }
            } else {
                $Body = [pscustomobject]@{
                    Results = "Invalid tenant: $TenantFilter"
                }
            }
        }
    } catch {
        Write-Information "ExoRequest Error: $($_.Exception.Message)"
    }
    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = ConvertTo-Json -InputObject $Body -Compress
        })
}
