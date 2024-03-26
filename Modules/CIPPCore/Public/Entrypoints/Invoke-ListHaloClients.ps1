using namespace System.Net

Function Invoke-ListHaloClients {
        <#
    .FUNCTIONALITY
    Entrypoint
    #>
        [CmdletBinding()]
        param($Request, $TriggerMetadata)

        $APIName = $TriggerMetadata.FunctionName
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'


        # Write to the Azure Functions log stream.
        Write-Host 'PowerShell HTTP trigger function processed a request.'

        # Interact with query parameters or the body of the request.
        try {
                $Table = Get-CIPPTable -TableName Extensionsconfig
                $Configuration = ((Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json).HaloPSA
                $Token = Get-HaloToken -configuration $Configuration
                $i = 1
                $RawHaloClients = do {
                        $Result = Invoke-RestMethod -Uri "$($Configuration.ResourceURL)/Client?page_no=$i&page_size=999&pageinate=true" -ContentType 'application/json' -Method GET -Headers @{Authorization = "Bearer $($token.access_token)" }
                        $Result.clients | Select-Object * -ExcludeProperty logo
                        $i++
                        $pagecount = [Math]::Ceiling($Result.record_count / 999)
                } while ($i -le $pagecount)
                $HaloClients = $RawHaloClients | ForEach-Object {
                        [PSCustomObject]@{
                                label = $_.name
                                value = $_.id
                        }
                }
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
