function Invoke-ExecCIPPDBCacheAdmin {
    <#
    .SYNOPSIS
        SuperAdmin browse / remove / empty for CIPPDB (CippReportingDB) cache collections.

    .DESCRIPTION
        Typed alternative to Table Maintenance for the reporting cache. List returns decoded
        cache objects stamped with CIPPPartitionKey / CIPPRowKey / CIPPETag so the UI can
        delete by storage key. Empty clears an entire type for a tenant (or AllTenants).

    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.SuperAdmin.ReadWrite
    #>
    [CmdletBinding()]
    param (
        $Request,
        $TriggerMetadata
    )

    $APIName = $TriggerMetadata.FunctionName
    $Body = $Request.Body
    $Action = [string]$Body.Action
    $TenantFilter = [string]$Body.TenantFilter
    $Type = [string]$Body.Type

    if ([string]::IsNullOrWhiteSpace($Action)) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'Error: Action is required (List, Remove, Empty)' }
            })
    }

    try {
        switch ($Action) {
            'List' {
                if ([string]::IsNullOrWhiteSpace($TenantFilter) -or [string]::IsNullOrWhiteSpace($Type)) {
                    throw 'List requires TenantFilter and Type'
                }

                $IsAllTenants = $TenantFilter -eq 'AllTenants'
                $DbTenant = if ($IsAllTenants) { 'allTenants' } else { $TenantFilter }
                $Rows = @(Get-CIPPDbItem -TenantFilter $DbTenant -Type $Type)
                $CountRowKey = "$Type-Count"

                $Results = foreach ($Row in $Rows) {
                    if ($Row.RowKey -eq $CountRowKey) { continue }
                    if ([string]::IsNullOrWhiteSpace($Row.Data)) { continue }

                    try {
                        $Parsed = [CIPP.CippJson]::ConvertFromJson($Row.Data, $null)
                    } catch {
                        Write-Information "Skipping unparseable CippReportingDB row for '$($Row.PartitionKey)'/'$Type': $($_.Exception.Message)"
                        continue
                    }

                    foreach ($Record in @($Parsed)) {
                        if ($Record -isnot [System.Management.Automation.PSObject] -and $Record -isnot [PSCustomObject]) {
                            $Record = [PSCustomObject]@{ Value = $Record }
                        }
                        $RecordProps = [ordered]@{
                            CIPPPartitionKey = $Row.PartitionKey
                            CIPPRowKey       = $Row.RowKey
                            CIPPETag         = $Row.ETag
                        }
                        if ($IsAllTenants) {
                            $RecordProps['Tenant'] = $Row.PartitionKey
                        }
                        $Record | Add-Member -NotePropertyMembers $RecordProps -Force
                        $Record
                    }
                }

                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::OK
                        Body       = @{ Results = @($Results) }
                    })
            }

            'Remove' {
                if ([string]::IsNullOrWhiteSpace($Type)) {
                    throw 'Remove requires Type'
                }

                $Rows = @($Body.Rows)
                if ($Rows.Count -eq 0) {
                    throw 'Remove requires Rows with CIPPPartitionKey/CIPPRowKey (or PartitionKey/RowKey)'
                }

                # Deduplicate by partition+row so array-unrolled List rows sharing one entity delete once
                $Seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $Removed = 0
                foreach ($Row in $Rows) {
                    $PartitionKey = [string]($Row.CIPPPartitionKey ?? $Row.PartitionKey ?? $TenantFilter)
                    $RowKey = [string]($Row.CIPPRowKey ?? $Row.RowKey)
                    $ETag = [string]($Row.CIPPETag ?? $Row.ETag)
                    if ([string]::IsNullOrWhiteSpace($PartitionKey) -or [string]::IsNullOrWhiteSpace($RowKey)) {
                        continue
                    }
                    $DedupKey = "$PartitionKey|$RowKey"
                    if (-not $Seen.Add($DedupKey)) { continue }

                    $RemoveParams = @{
                        TenantFilter = $PartitionKey
                        Type         = $Type
                        RowKey       = $RowKey
                    }
                    if ($ETag) { $RemoveParams.ETag = $ETag }
                    Remove-CIPPDbItem @RemoveParams
                    $Removed++
                }

                Write-LogMessage -API $APIName -tenant $TenantFilter -message "Removed $Removed $Type cache row(s)" -sev Warning
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::OK
                        Body       = @{ Results = "Removed $Removed $Type cache row(s)" }
                    })
            }

            'Empty' {
                if ([string]::IsNullOrWhiteSpace($TenantFilter) -or [string]::IsNullOrWhiteSpace($Type)) {
                    throw 'Empty requires TenantFilter and Type'
                }

                $ClearResult = Clear-CIPPDbCache -TenantFilter $TenantFilter -Type $Type
                Write-LogMessage -API $APIName -tenant $TenantFilter -message "Emptied $Type cache for $($ClearResult.Tenant): $($ClearResult.RemovedCount) row(s)" -sev Warning
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::OK
                        Body       = @{
                            Results = "Emptied $Type cache for $($ClearResult.Tenant): $($ClearResult.RemovedCount) row(s) removed"
                            Details = $ClearResult
                        }
                    })
            }

            default {
                throw "Unknown Action '$Action'. Use List, Remove, or Empty."
            }
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $APIName -tenant $TenantFilter -message "CIPPDB cache admin failed: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = $ErrorMessage.NormalizedError }
            })
    }
}
