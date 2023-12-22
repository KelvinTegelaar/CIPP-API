function Invoke-CippGraphWebhookProcessing {
    [CmdletBinding()]
    param (
        $Data,
        $CIPPID,
        $WebhookInfo    
    )

    $Table = Get-CIPPTable -TableName Extensionsconfig

    $Configuration = ((Get-AzDataTableEntity @Table).config | ConvertFrom-Json)

        Switch ($WebhookInfo.Resource) {
            'devices' {
                # NinjaOne Extension
                if ($Configuration.NinjaOne.Enabled -eq $True) {
                Invoke-NinjaOneDeviceWebhook -Data $Data -Configuration $Configuration.NinjaOne
                }
            }
        }
        

    }
