using namespace System.Net

function Invoke-ListTeamsActivity {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Teams.Activity.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'


    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    try {
        $Type = $Request.Query.Type
        $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/reports/get$($Type)Detail(period='D30')" -tenantid $TenantFilter | ConvertFrom-Csv | Select-Object @{ Name = 'UPN'; Expression = { $_.'User Principal Name' } },
        @{ Name = 'LastActive'; Expression = { $_.'Last Activity Date' } },
        @{ Name = 'TeamsChat'; Expression = { $_.'Team Chat Message Count' } },
        @{ Name = 'CallCount'; Expression = { $_.'Call Count' } },
        @{ Name = 'MeetingCount'; Expression = { $_.'Meeting Count' } }

        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::InternalServerError
        $GraphRequest = $ErrorMessage
    }

    return @{
        StatusCode = $StatusCode
        Body       = @($GraphRequest)
    }
}
