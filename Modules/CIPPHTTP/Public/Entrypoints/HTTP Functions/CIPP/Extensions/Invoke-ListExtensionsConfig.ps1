function Invoke-ListExtensionsConfig {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Extension.Read
    .DESCRIPTION
        Lists the current CIPP extension configuration, including settings for HaloPSA, NinjaOne, Hudu, and other integrations.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $Table = Get-CIPPTable -TableName Extensionsconfig
    try {
        $Config = (Get-CIPPAzDataTableEntity @Table).config
        if ($Config -and (Test-Json -Json $Config -ErrorAction SilentlyContinue)) {
            $Body = $Config | ConvertFrom-Json -Depth 10 -ErrorAction Stop
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
            # Screens read this to decide which CSP provider is active, so a flagged-off External CSP reads as disabled.
            if ($Body.ExternalCSP.Enabled -eq $true -and (Get-CIPPFeatureFlag -Id 'ExternalCSP').Enabled -ne $true) {
                $Body.ExternalCSP.Enabled = $false
            }
        } else {
            $Body = @{}
        }
    } catch {
        Write-Information (Get-CippException -Exception $_ | ConvertTo-Json)
        $Body = @{}
    }
    return [HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    }

}
