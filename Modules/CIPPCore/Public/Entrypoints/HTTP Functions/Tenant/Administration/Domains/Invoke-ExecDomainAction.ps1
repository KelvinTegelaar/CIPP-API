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
    $TenantFilter = $Request.Body.tenantFilter
    $DomainName = $Request.Body.domain
    $Action = $Request.Body.Action

    try {
        if ([string]::IsNullOrWhiteSpace($DomainName)) {
            throw 'Domain name is required'
        }

        if ([string]::IsNullOrWhiteSpace($Action)) {
            throw 'Action is required'
        }

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

                Write-LogMessage -headers $Request.Headers -API $APIName -tenant $TenantFilter -message "Verified domain $DomainName" -Sev 'Info'
                $StatusCode = [HttpStatusCode]::OK
            }
            'delete' {
                Write-Information "Deleting domain $DomainName from tenant $TenantFilter"

                $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/domains/$DomainName" -tenantid $TenantFilter -type DELETE -AsApp $true

                $Result = @{
                    resultText = "Domain $DomainName has been deleted successfully."
                    state      = 'success'
                }

                Write-LogMessage -headers $Request.Headers -API $APIName -tenant $TenantFilter -message "Deleted domain $DomainName" -Sev 'Info'
                $StatusCode = [HttpStatusCode]::OK
            }
            'setDefault' {
                Write-Information "Setting domain $DomainName as default for tenant $TenantFilter"

                $Body = @{
                    isDefault = $true
                } | ConvertTo-Json -Compress

                $GraphRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/domains/$DomainName" -tenantid $TenantFilter -type PATCH -body $Body -AsApp $true

                $Result = @{
                    resultText = "Domain $DomainName has been set as the default domain successfully."
                    state      = 'success'
                }

                Write-LogMessage -headers $Request.Headers -API $APIName -tenant $TenantFilter -message "Set domain $DomainName as default" -Sev 'Info'
                $StatusCode = [HttpStatusCode]::OK
            }
            default {
                throw "Invalid action: $Action"
            }
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = @{
            resultText = "Failed to perform action on domain $DomainName`: $($ErrorMessage.NormalizedError)"
            state      = 'error'
        }
        Write-LogMessage -headers $Request.Headers -API $APIName -tenant $TenantFilter -message "Failed to perform action on domain $DomainName`: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::Forbidden
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = $Result }
        })
}
