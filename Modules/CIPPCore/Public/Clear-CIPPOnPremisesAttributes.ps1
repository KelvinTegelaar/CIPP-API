function Clear-CIPPOnPremisesAttributes {
    <#
    .SYNOPSIS
        Clears leftover on-premises attributes from a cloud-only user.
    .DESCRIPTION
        PATCHes the selected onPremises* attributes to null via Graph beta. Only cloud-only users can be
        updated (Graph rejects synced ones). The values being cleared are written to the log entry as the
        rollback record Microsoft recommends keeping.
        https://learn.microsoft.com/entra/identity/hybrid/connect/tshoot-clear-on-premises-attributes
    #>
    [CmdletBinding()]
    param (
        $TenantFilter,
        $UserID,
        $Username, # Optional - used for better logging
        $Headers,
        $APIName = 'Clear On-Premises Attributes',
        [string[]]$Attributes # Attribute names to clear; empty clears every clearable attribute
    )

    # The on-premises attributes Microsoft documents as clearable on cloud-only users
    $ClearableAttributes = @(
        'onPremisesDistinguishedName', 'onPremisesDomainName', 'onPremisesImmutableId', 'onPremisesObjectIdentifier',
        'onPremisesSamAccountName', 'onPremisesSecurityIdentifier', 'onPremisesUserPrincipalName'
    )
    $DisplayName = $Username ?? $UserID

    try {
        # Names arrive from the request body: normalise casing and reject anything outside the documented list
        if (-not $Attributes) { $Attributes = $ClearableAttributes }
        $Attributes = @(foreach ($Attribute in $Attributes) {
                $Match = $ClearableAttributes | Where-Object { $_ -eq $Attribute } | Select-Object -First 1
                if (-not $Match) { throw "'$Attribute' is not a clearable on-premises attribute. Allowed: $($ClearableAttributes -join ', ')" }
                $Match
            })
        $AttributeList = $Attributes -join ', '

        try {
            $SelectProps = (@('id', 'userPrincipalName', 'displayName') + $ClearableAttributes) -join ','
            $UserObj = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($UserID)?`$select=$SelectProps" -tenantid $TenantFilter -ErrorAction SilentlyContinue
        } catch {
            # User might be soft deleted (offboarding flow), restore it so the attributes can be cleared
            $DeletedUser = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/directory/deletedItems/$UserID" -tenantid $TenantFilter
            if ($DeletedUser.id) {
                $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/directory/deletedItems/$UserID/restore" -tenantid $TenantFilter -type POST
                Write-LogMessage -headers $Headers -API $APIName -message "Restored deleted user $UserID to clear on-premises attributes" -sev Info -tenant $TenantFilter
            }
        }

        # Keep the values being wiped in the log entry: Microsoft advises backing them up first, and the log is the rollback record
        $Previous = [ordered]@{}
        $Body = @{}
        foreach ($Attribute in $Attributes) {
            $Previous[$Attribute] = $UserObj.$Attribute
            $Body[$Attribute] = $null
        }
        $Body = ConvertTo-Json -InputObject $Body -Depth 5 -Compress
        $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$UserID" -tenantid $TenantFilter -type PATCH -body $Body -AsApp $true

        $Result = "Successfully cleared $AttributeList for user $DisplayName"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -sev Info -tenant $TenantFilter -LogData $Previous
        return $Result
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to clear on-premises attributes ($($Attributes -join ', ')) for $DisplayName. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -sev Error -tenant $TenantFilter -LogData $ErrorMessage
        throw $Result
    }
}
