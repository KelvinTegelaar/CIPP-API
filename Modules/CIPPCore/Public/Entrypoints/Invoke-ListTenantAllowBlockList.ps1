using namespace System.Net

function Invoke-ListTenantAllowBlockList {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.SpamFilter.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    $ListTypes = 'Sender', 'Url', 'FileHash', 'IP'
    try {
        $Results = $ListTypes | ForEach-Object -Parallel {
            Import-Module CIPPCore
            $TempResults = New-ExoRequest -tenantid $using:TenantFilter -cmdlet 'Get-TenantAllowBlockListItems' -cmdParams @{ListType = $_ }
            $TempResults | Add-Member -MemberType NoteProperty -Name ListType -Value $_
            $TempResults | Select-Object -ExcludeProperty *'@data.type'*, *'(DateTime])'*
        } -ThrottleLimit 5

        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $Results = $ErrorMessage
    }

    return @{
        StatusCode = $StatusCode
        Body       = @($Results)
    }
}
