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

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $BlockList = @(
        'Get-GraphToken'
        'Get-GraphTokenFromCert'
        'New-CIPPCertificateAssertion'
        'Get-ClassicAPIToken'
        'Get-CIPPSAMCertificate'
        'New-CIPPSAMCertificate'
        'Set-CIPPSAMCertificate'
        'Update-CIPPSAMCertificate'
    )

    $Function = $Request.Body.FunctionName
    $Params = if ($Request.Body.Parameters) {
        $Request.Body.Parameters | ConvertTo-Json -Compress -ErrorAction Stop | ConvertFrom-Json -AsHashtable
    } else {
        @{}
    }
    $ParamKeys = if ($Params.Keys) { @($Params.Keys) -join ', ' } else { 'none' }

    if (Get-Command -Module CIPPCore -Name $Function -and $BlockList -notcontains $Function) {
        try {
            $Results = & $Function @Params
            if (!$Results) {
                $Results = "Function $Function executed successfully"
            }
            Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message "SuperAdmin CippFunction ran '$Function' (param keys: $ParamKeys)" -Sev 'Info'
            $StatusCode = [HttpStatusCode]::OK
        } catch {
            $Results = $_.Exception.Message
            Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message "SuperAdmin CippFunction '$Function' failed: $Results" -Sev 'Error' -LogData (Get-CippException -Exception $_)
            $StatusCode = [HttpStatusCode]::InternalServerError
        }
    } else {
        $Results = "Function $Function not found or not allowed"
        Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message "SuperAdmin CippFunction blocked: $Results" -Sev 'Error'
        $StatusCode = [HttpStatusCode]::NotFound
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })
}
