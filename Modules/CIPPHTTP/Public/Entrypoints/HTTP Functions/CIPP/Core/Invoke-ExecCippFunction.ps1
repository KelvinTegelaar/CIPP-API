function Invoke-ExecCippFunction {
    <#
    .SYNOPSIS
        Execute a CIPPCore function
    .DESCRIPTION
        This function is used to execute a CIPPCore function from an HTTP request. This is advanced functionality used for external integrations or SuperAdmin functionality.
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.SuperAdmin.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    # Functions that must never be callable via this endpoint regardless of role.
    # Prefer expanding this list over shrinking it.
    $BlockList = @(
        'Get-GraphToken'
        'Get-GraphTokenFromCert'
        'Get-ClassicAPIToken'
        'Get-CIPPSamKey'
        'Get-CIPPAzDataTableEntity'
        'Add-CIPPAzDataTableEntity'
        'Update-AzDataTableEntity'
        'Remove-AzDataTableEntity'
        'Get-CIPPTable'
        'New-CIPPGraphPermission'
        'Set-CIPPSamKey'
        'Invoke-CIPPRestMethod'
        'New-GraphPostRequest'
        'New-GraphPatchRequest'
        'New-GraphDeleteRequest'
        'Remove-CIPPGraphPermission'
    )

    $Function = $Request.Body.FunctionName

    # Validate function name: must be a valid PowerShell verb-noun identifier
    if ([string]::IsNullOrWhiteSpace($Function) -or $Function -notmatch '^[A-Za-z]+-[A-Za-z0-9]+$') {
        Write-LogMessage -headers $Request.Headers -API 'ExecCippFunction' -message "Rejected invalid function name: '$Function'" -Sev 'Warning'
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = 'Invalid function name'
            })
    }

    $Params = if ($Request.Body.Parameters) {
        $Request.Body.Parameters | ConvertTo-Json -Compress -ErrorAction Stop | ConvertFrom-Json -AsHashtable
    } else {
        @{}
    }

    if ((Get-Command -Module CIPPCore -Name $Function -ErrorAction SilentlyContinue) -and $BlockList -notcontains $Function) {
        Write-LogMessage -headers $Request.Headers -API 'ExecCippFunction' -message "Executing CIPPCore function: $Function" -Sev 'Info'
        try {
            $Results = & $Function @Params
            if (!$Results) {
                $Results = "Function $Function executed successfully"
            }
            $StatusCode = [HttpStatusCode]::OK
        } catch {
            Write-LogMessage -headers $Request.Headers -API 'ExecCippFunction' -message "Function $Function failed: $($_.Exception.Message)" -Sev 'Error'
            $Results = 'An error occurred executing the requested function'
            $StatusCode = [HttpStatusCode]::InternalServerError
        }
    } else {
        Write-LogMessage -headers $Request.Headers -API 'ExecCippFunction' -message "Blocked call to function: '$Function'" -Sev 'Warning'
        $Results = 'Function not found or not allowed'
        $StatusCode = [HttpStatusCode]::NotFound
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })
}
