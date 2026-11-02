function New-CippMcpRegistrationError {
    <#
    .SYNOPSIS
        Builds an RFC 7591 dynamic client registration error response.
    .DESCRIPTION
        Registration errors are HTTP 400 with a JSON body of { error, error_description }.
        Logs the rejection and returns the ready-to-send HttpResponseContext for
        Invoke-PublicMcpRegister.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Code,

        [Parameter(Mandatory)]
        [string]$Description,

        [Parameter(Mandatory)]
        [hashtable]$Headers
    )

    Write-LogMessage -API 'PublicMcpRegister' -message "Rejected MCP client registration: $Description" -Sev 'Warning'
    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Headers    = $Headers
            Body       = (@{ error = $Code; error_description = $Description } | ConvertTo-Json -Compress)
        })
}
