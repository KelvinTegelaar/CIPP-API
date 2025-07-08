using namespace System.Net

Function Invoke-ListHaloClients {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Extension.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'


    # Interact with query parameters or the body of the request.
    try {
        $Table = Get-CIPPTable -TableName Extensionsconfig
        $Configuration = ((Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json).HaloPSA
        $Token = Get-HaloToken -configuration $Configuration
        $i = 1
        $RawHaloClients = do {
            $Result = Invoke-RestMethod -Uri "$($Configuration.ResourceURL)/Client?page_no=$i&page_size=999&pageinate=true" -ContentType 'application/json' -Method GET -Headers @{Authorization = "Bearer $($Token.access_token)" }
            $Result.clients | Select-Object * -ExcludeProperty logo
            $i++
            $PageCount = [Math]::Ceiling($Result.record_count / 999)
        } while ($i -le $PageCount)
        $HaloClients = $RawHaloClients | ForEach-Object {
            [PSCustomObject]@{
                label = $_.name
                value = $_.id
            }
        }
        Write-Host "Found $($HaloClients.Count) Halo Clients"
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $HaloClients = $ErrorMessage
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($HaloClients)
        })

}
