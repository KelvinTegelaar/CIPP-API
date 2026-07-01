function New-CippExtAlert {
    [CmdletBinding()]
    param (
        [switch]$TestRun = $false,
        [pscustomobject]$Alert
    )
    #Get the current CIPP Alerts table and see what system is configured to receive alerts
    $Table = Get-CIPPTable -TableName Extensionsconfig
    $Configuration = (Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json -Depth 10 -ErrorAction SilentlyContinue
    $MappingTable = Get-CIPPTable -TableName CippMapping

    foreach ($ConfigItem in $Configuration.psobject.properties.name) {
        switch ($ConfigItem) {
            'HaloPSA' {
                if ($Configuration.HaloPSA.enabled) {
                    $MappingFile = Get-CIPPAzDataTableEntity @MappingTable -Filter "PartitionKey eq 'HaloMapping'"
                    $TenantId = (Get-Tenants -TenantFilter $Alert.TenantId).customerId
                    Write-Host "TenantId: $TenantId"
                    $MappedId = ($MappingFile | Where-Object { $_.RowKey -eq $TenantId }).IntegrationId
                    Write-Host "MappedId: $MappedId"
                    if (!$mappedId) { $MappedId = 1 }
                    Write-Host "MappedId: $MappedId"

                    $TicketParams = @{
                        Title       = $Alert.AlertTitle
                        Description = $Alert.AlertText
                        Client      = $MappedId
                    }

                    if ($Alert.AffectedUser -and $Configuration.HaloPSA.LinkTicketsToUsers) {
                        $UPN = $Alert.AffectedUser.UPN
                        $OID = $Alert.AffectedUser.AzureOID
                        $Display = $Alert.AffectedUser.DisplayName

                        # Best-effort: resolve UPN -> Azure Object ID via Graph if we don't already have it.
                        # Failure here is non-fatal; Get-HaloUser will still try the email-based lookup.
                        if (-not $OID -and $UPN -and $Alert.TenantId) {
                            try {
                                $EncodedUPN = [System.Uri]::EscapeDataString($UPN)
                                $GraphUser = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$EncodedUPN`?`$select=id,displayName,userPrincipalName" -tenantid $Alert.TenantId -AsApp $true
                                if ($GraphUser.id) { $OID = $GraphUser.id }
                                if (-not $Display -and $GraphUser.displayName) { $Display = $GraphUser.displayName }
                            } catch {
                                Write-Information "Could not resolve Graph user for $UPN in tenant $($Alert.TenantId): $($_.Exception.Message)"
                            }
                        }

                        if ($UPN) { $TicketParams.UserUPN = $UPN }
                        if ($OID) { $TicketParams.AzureOID = $OID }
                        if ($Display) { $TicketParams.DisplayName = $Display }
                    }

                    New-HaloPSATicket @TicketParams
                }
            }
            'Gradient' {
                if ($Configuration.Gradient.enabled) {
                    New-GradientAlert -Title $Alert.AlertTitle -Description $Alert.AlertText -Client $Alert.TenantId
                }
            }
        }
    }

}
