using namespace System.Net

function Invoke-ExecUpdateDriftDeviation {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Standards.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    try {
        $TenantFilter = $Request.Body.TenantFilter

        if ($Request.Body.RemoveDriftCustomization) {
            $Table = Get-CippTable -tablename 'tenantDrift'
            $Filter = "PartitionKey eq '$TenantFilter'"
            $ExistingDeviations = Get-CIPPAzDataTableEntity @Table -Filter $Filter
            foreach ($Deviation in $ExistingDeviations) {
                Remove-AzDataTableEntity @Table -Entity $Deviation
            }
            $Results = @([PSCustomObject]@{
                    success = $true
                    result  = "All drift customizations removed for tenant $TenantFilter"
                })
            Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Removed all drift customizations for tenant $TenantFilter" -Sev 'Info'
        } else {
            $Deviations = $Request.Body.deviations
            $Reason = $Request.Body.reason
            $Results = foreach ($Deviation in $Deviations) {
                try {
                    $user = $request.headers.'x-ms-client-principal'
                    $username = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($user)) | ConvertFrom-Json).userDetails
                    $Result = Set-CIPPDriftDeviation -TenantFilter $TenantFilter -StandardName $Deviation.standardName -Status $Deviation.status -Reason $Reason -user $username
                    [PSCustomObject]@{
                        success = $true
                        result  = $Result
                    }
                    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Updated drift deviation status for $($Deviation.standardName) to $($Deviation.status) with reason: $Reason" -Sev 'Info'
                    if ($Deviation.status -eq 'DeniedRemediate') {
                        $Setting = $Deviation.standardName -replace 'standards.', ''
                        $StandardTemplate = Get-CIPPTenantAlignment -TenantFilter $TenantFilter | Where-Object -Property standardType -EQ 'drift'
                        $StandardTemplate = $StandardTemplate.$Setting
                        $StandardTemplate.action = @(
                            @{label = 'Report'; value = 'Report' },
                            @{ label = 'Remediate'; value = 'Remediate' }
                        )
                        #idea here is to make a system job that triggers the remediation process, so that users can click on "Deniedremediate"
                        #That job then launches a single standard run, it gets the same input as an orch, but is just a scheduled job.

                    }
                    if ($Deviation.status -eq 'deniedDelete') {
                        #Here we look at the policy ID received and the type, and nuke it.
                    }
                } catch {
                    [PSCustomObject]@{
                        standardName = $Deviation.standardName
                        success      = $false
                        error        = $_.Exception.Message
                    }
                    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Failed to update drift deviation for $($Deviation.standardName): $($_.Exception.Message)" -Sev 'Error'
                }
            }
        }

        $Body = @{ Results = @($Results) }

        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = $Body
            })

    } catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Failed to update drift deviation: $($_.Exception.Message)" -Sev 'Error'
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{error = $_.Exception.Message }
            })
    }
}
