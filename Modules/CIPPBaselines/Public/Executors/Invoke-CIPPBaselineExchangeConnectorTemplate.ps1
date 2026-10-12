function Invoke-CIPPBaselineExchangeConnectorTemplate {
    <#
    .SYNOPSIS
        ExchangeConnectorTemplate executor: creates or rewrites the connector.
    .DESCRIPTION
        New- when absent, Set- when present, with the cmdlet noun picked by the template's
        direction (InboundConnector/OutboundConnector) - the classic's exact write. The full
        template body is applied on every remediation run, which pairs with
        checkBeforeRun:false: the compare only grades presence, and the rewrite is what
        repairs setting drift it cannot see.

        The comment field runs through Get-CIPPTextReplacement first (tenant tokens like
        %tenantname%), and defaults to 'no comment' when the template has none - both
        carried from the classic.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $Body = $Current.connectorBody
    $Direction = "$($Current.direction)"
    if (-not $Body -or $Direction -notin @('inbound', 'outbound')) { return }

    if ($Body.comment) {
        $Body.comment = Get-CIPPTextReplacement -Text $Body.comment -TenantFilter $TenantFilter
    } else {
        $Body | Add-Member -NotePropertyName 'comment' -NotePropertyValue 'no comment' -Force
    }

    if ($Current.deployed -eq $true) {
        $Body | Add-Member -NotePropertyName 'Identity' -NotePropertyValue "$($Current.existingIdentity)" -Force
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet "Set-$($Direction)connector" -cmdParams $Body -useSystemMailbox $true
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Updated $Direction connector '$($Body.name)'." -Sev 'Info'
    } else {
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet "New-$($Direction)connector" -cmdParams $Body -useSystemMailbox $true
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Created $Direction connector '$($Body.name)'." -Sev 'Info'
    }
}
