using namespace System.Net

Function Invoke-ListExtensionsConfig {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Extension.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    $Table = Get-CIPPTable -TableName Extensionsconfig
    try {
        $Body = (Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json -Depth 10 -ErrorAction Stop
        if ($Body.HaloPSA.TicketType -and !$Body.HaloPSA.TicketType.value) {
            # translate ticket type to autocomplete format
            Write-Information "Ticket Type: $($Body.HaloPSA.TicketType)"
            $Types = Get-HaloTicketType
            $Type = $Types | Where-Object { $_.id -eq $Body.HaloPSA.TicketType }
            #Write-Information ($Type | ConvertTo-Json)
            if ($Type) {
                $Body.HaloPSA.TicketType = @{
                    label = $Type.name
                    value = $Type.id
                }
            }
        }
    } catch {
        Write-Information (Get-CippException -Exception $_ | ConvertTo-Json)
        $Body = @{}
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
