function Invoke-ListDirectoryObjects {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $TenantFilter = $Request.Body.tenantFilter
    $AsApp = $Request.Body.asApp
    $Ids = $Request.Body.ids

    $BaseUri = 'https://graph.microsoft.com/beta/directoryObjects/getByIds'
    if ($Request.Body.'$select') {
        $Uri = '{0}?$select={1}' -f $BaseUri, $Request.Body.'$select'
    } else {
        $Uri = $BaseUri
    }

    $Body = @{
        ids = $Ids
    } | ConvertTo-Json -Depth 10

    try {
        $Results = New-GraphPOSTRequest -tenantid $TenantFilter -uri $Uri -body $Body -AsApp $AsApp
        $StatusCode = [System.Net.HttpStatusCode]::OK
    } catch {
        $StatusCode = [System.Net.HttpStatusCode]::BadRequest
        $Results = $_.Exception.Message
        Write-Warning "Error retrieving directory objects: $Results"
        Write-Information $_.InvocationInfo.PositionMessage
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })
}
