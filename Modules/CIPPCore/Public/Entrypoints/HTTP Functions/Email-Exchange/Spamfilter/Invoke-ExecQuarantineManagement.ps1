using namespace System.Net

function Invoke-ExecQuarantineManagement {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.SpamFilter.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'


    # Interact with query parameters or the body of the request.
    try {
        $TenantFilter = $Request.Body.tenantFilter | Select-Object -First 1
        $params = @{
            AllowSender  = [boolean]$Request.Body.AllowSender
            ReleaseToAll = $true
            ActionType   = ($Request.Body.Type | Select-Object -First 1)
        }
        if ($Request.Body.Identity -is [string]) {
            $params['Identity'] = $Request.Body.Identity
        } else {
            $params['Identities'] = $Request.Body.Identity
        }
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Release-QuarantineMessage' -cmdParams $Params
        $Result = "Successfully processed $($Request.Body.Identity)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to process Quarantine Management: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }
    return @{
        StatusCode = $StatusCode
        Body       = @{ Results = $Result }
    }
}
