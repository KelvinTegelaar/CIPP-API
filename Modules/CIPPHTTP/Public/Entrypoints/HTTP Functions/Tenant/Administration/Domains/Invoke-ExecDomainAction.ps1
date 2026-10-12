function Invoke-ExecDomainAction {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Administration.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter
    $DomainName = $Request.Body.domain
    $Action = $Request.Body.Action

    if ([string]::IsNullOrWhiteSpace($DomainName)) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{'Results' = @{ resultText = 'Domain name is required'; state = 'error' } }
            })
    }

    if ([string]::IsNullOrWhiteSpace($Action)) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{'Results' = @{ resultText = 'Action is required'; state = 'error' } }
            })
    }

    if ($Action -notin @('verify', 'delete', 'setDefault')) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{'Results' = @{ resultText = "Invalid action: $Action"; state = 'error' } }
            })
    }

    try {
        switch ($Action) {
            'verify' {
                Write-Information "Verifying domain $DomainName for tenant $TenantFilter"

                $Body = @{
                    verificationDnsRecordCollection = @()
                } | ConvertTo-Json -Compress

                $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/domains/$DomainName/verify" -tenantid $TenantFilter -type POST -body $Body -AsApp $true

                $Result = @{
                    resultText = "Domain $DomainName has been verified successfully."
                    state      = 'success'
                }

                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Verified domain $DomainName" -Sev 'Info'
            }
            'delete' {
                Write-Information "Deleting domain $DomainName from tenant $TenantFilter"

                $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/domains/$DomainName" -tenantid $TenantFilter -type DELETE -AsApp $true

                $Result = @{
                    resultText = "Domain $DomainName has been deleted successfully."
                    state      = 'success'
                }

                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Deleted domain $DomainName" -Sev 'Info'
            }
            'setDefault' {
                Write-Information "Setting domain $DomainName as default for tenant $TenantFilter"

                $Body = @{
                    isDefault = $true
                } | ConvertTo-Json -Compress

                $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/domains/$DomainName" -tenantid $TenantFilter -type PATCH -body $Body -AsApp $true

                $Result = @{
                    resultText = "Domain $DomainName has been set as the default domain successfully."
                    state      = 'success'
                }

                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Set domain $DomainName as default" -Sev 'Info'
            }
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = @{
            resultText = "Failed to perform action on domain $DomainName`: $($ErrorMessage.NormalizedError)"
            state      = 'error'
        }
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to perform action on domain $DomainName`: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = ($StatusCode ?? [HttpStatusCode]::OK)
            Body       = @{'Results' = $Result }
        })
}
