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

    $BlockList = @(
        'Get-GraphToken'
        'Get-GraphTokenFromCert'
        'Get-ClassicAPIToken'
    )

    $Function = $Request.Body.FunctionName
    $Params = if ($Request.Body.Parameters) {
        $Request.Body.Parameters | ConvertTo-Json -Compress -ErrorAction Stop | ConvertFrom-Json -AsHashtable
    } else {
        @{}
    }

    if (Get-Command -Module CIPPCore -Name $Function -and $BlockList -notcontains $Function) {
        try {
            $Results = & $Function @Params
            if (!$Results) {
                $Results = "Function $Function executed successfully"
            }
            $StatusCode = [HttpStatusCode]::OK
        } catch {
            $Results = $_.Exception.Message
            $StatusCode = [HttpStatusCode]::InternalServerError
        }
    } else {
        $Results = "Function $Function not found or not allowed"
        $StatusCode = [HttpStatusCode]::NotFound
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })
}