function Update-CIPPSAMSecret {
    <#
    .SYNOPSIS
        Mints a new CIPP-SAM client secret, stores it, and records its keyId in AppCache.
    .DESCRIPTION
        If storing the secret fails it is removed from the app again, so an unstored secret never
        becomes the newest credential and suppresses the next rotation. Throws on failure.
        Returns @{ KeyId; EndDateTime; Rotated }.
    .FUNCTIONALITY
        Internal
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '')]
    [CmdletBinding()]
    param(
        [string]$ApplicationObjectId,
        [string]$DisplayName = 'UpdateTokens',
        [ValidateSet('ScheduledRotation', 'Manual', 'Setup')]
        [string]$Source = 'ScheduledRotation',
        $Headers,
        [string]$APIName = 'Update Tokens'
    )

    $AppId = $env:ApplicationID
    if (-not $ApplicationObjectId) {
        $ApplicationObjectId = (New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/applications(appId='$AppId')?`$select=id" -NoAuthCheck $true -AsApp $true -ErrorAction Stop).id
    }

    try {
        $AppPolicyStatus = Update-AppManagementPolicy
        Write-Information $AppPolicyStatus.PolicyAction
    } catch {
        Write-Warning "Error updating app management policy $($_.Exception.Message)."
    }

    $Body = ConvertTo-Json -Compress -InputObject @{ passwordCredential = @{ displayName = $DisplayName } }
    try {
        $AppSecret = New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/applications/$ApplicationObjectId/addPassword" -Body $Body -NoAuthCheck $true -AsApp $true -ErrorAction Stop
    } catch {
        Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message "$Source`: failed to create a new CIPP-SAM client secret for $AppId`: $($_.Exception.Message)" -Sev 'Error' -LogData (Get-CippException -Exception $_)
        throw
    }

    try {
        if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') {
            $DevTable = Get-CIPPTable -tablename 'DevSecrets'
            $Secret = Get-CIPPAzDataTableEntity @DevTable -Filter "PartitionKey eq 'Secret' and RowKey eq 'Secret'"
            if (-not $Secret) { throw 'The DevSecrets row does not exist.' }
            $Secret | Add-Member -MemberType NoteProperty -Name 'ApplicationSecret' -Value $AppSecret.secretText -Force
            Add-AzDataTableEntity @DevTable -Entity $Secret -Force
        } else {
            Set-CippKeyVaultSecret -VaultName (Get-CippKeyVaultName) -Name 'ApplicationSecret' -SecretValue (ConvertTo-SecureString -String $AppSecret.secretText -AsPlainText -Force)
        }
    } catch {
        Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message "$Source`: failed to store the new CIPP-SAM client secret (keyId $($AppSecret.keyId)) for $AppId. Rolling it back." -Sev 'Error' -LogData (Get-CippException -Exception $_)
        try {
            New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/applications/$ApplicationObjectId/removePassword" -Body "{`"keyId`":`"$($AppSecret.keyId)`"}" -NoAuthCheck $true -AsApp $true -ErrorAction Stop
            Write-Information "Rolled back unstored application secret with keyId $($AppSecret.keyId)."
        } catch {
            Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message "Failed to roll back unstored CIPP-SAM client secret with keyId $($AppSecret.keyId) for $AppId." -Sev 'Error' -LogData (Get-CippException -Exception $_)
        }
        throw
    }

    $env:ApplicationSecret = $AppSecret.secretText

    # The secret is stored and usable; losing the keyId only degrades ownership tracking.
    try {
        $ConfigTable = Get-CIPPTable -tablename 'Config'
        $AppCache = Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'AppCache' and RowKey eq 'AppCache'"
        $null = Add-CIPPAzDataTableEntity @ConfigTable -Entity @{
            PartitionKey  = 'AppCache'
            RowKey        = 'AppCache'
            ApplicationId = [string]($AppCache.ApplicationId ?? $AppId)
            SecretKeyId   = [string]$AppSecret.keyId
        } -Force
        $null = Set-CIPPCredentialVersion
    } catch {
        Write-Warning "Could not record the new secret keyId in AppCache: $($_.Exception.Message)"
    }

    # Provenance lets the credential monitor label this secret as CIPP's own.
    $Actor = 'CIPP'
    try { $Actor = Set-CIPPSAMCredentialRecord -KeyId $AppSecret.keyId -Source $Source -Headers $Headers } catch { Write-Warning "Could not record the new secret's provenance: $($_.Exception.Message)" }

    $Detail = "new CIPP-SAM client secret created for $AppId (keyId $($AppSecret.keyId), expires $($AppSecret.endDateTime))."
    $Message = switch ($Source) {
        'ScheduledRotation' { "Scheduled rotation: $Detail No action needed." }
        'Manual' { "Manual rotation by $Actor`: $Detail" }
        'Setup' { "Setup by $Actor`: $Detail" }
    }
    Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message $Message -Sev 'Alert'

    try { $null = Compare-CIPPSAMCredentialSnapshot -Acknowledge $AppSecret.keyId } catch { Write-Warning "Could not refresh the SAM credential snapshot: $($_.Exception.Message)" }

    return @{
        KeyId       = $AppSecret.keyId
        EndDateTime = $AppSecret.endDateTime
        Rotated     = $true
    }
}
