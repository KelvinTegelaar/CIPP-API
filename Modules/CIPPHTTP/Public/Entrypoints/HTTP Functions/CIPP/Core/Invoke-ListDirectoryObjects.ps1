function Invoke-ListDirectoryObjects {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $TenantFilter = $Request.Body.partnerLookup ? $env:TenantID : $Request.Body.tenantFilter
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
        $Results = New-GraphPOSTRequest -tenantid $TenantFilter -uri $Uri -body $Body -AsApp $AsApp -NoAuthCheck $true
        $StatusCode = [System.Net.HttpStatusCode]::OK
    } catch {
        $StatusCode = [System.Net.HttpStatusCode]::BadRequest
        $Results = $_.Exception.Message
        Write-Warning "Error retrieving directory objects: $Results"
        Write-Information $_.InvocationInfo.PositionMessage
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })
}
