function Get-CIPPSAMCredentials {
    <#
    .SYNOPSIS
        Lists every secret and certificate on the CIPP-SAM app with its owner classification.
    .DESCRIPTION
        Ownership comes from the AppCache SecretKeyId and the stored SAM certificate thumbprint.
        Config 'SAMCredential' rows overlay admin labels and CIPP's own provenance (source/actor).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [string]$ApplicationId = $env:ApplicationID
    )

    $App = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/applications(appId='$ApplicationId')?`$select=id,appId,passwordCredentials,keyCredentials" -NoAuthCheck $true -AsApp $true -ErrorAction Stop

    $ConfigTable = Get-CIPPTable -tablename 'Config'
    $AppCache = Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'AppCache' and RowKey eq 'AppCache'"
    $OwnSecretKeyId = [string]$AppCache.SecretKeyId
    $Flags = @{}
    foreach ($Flag in @(Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'SAMCredential'")) {
        if ($Flag.RowKey) { $Flags[[string]$Flag.RowKey] = $Flag }
    }

    $StoredCertificate = $null
    try { $StoredCertificate = Get-CIPPSAMCertificate -SkipCache -ErrorAction Stop } catch { Write-Information "No stored SAM certificate: $($_.Exception.Message)" }
    $OwnThumbprint = [string]$StoredCertificate.Thumbprint
    $KnownThumbprints = [System.Collections.Generic.List[string]]::new()
    if ($OwnThumbprint) { $KnownThumbprints.Add($OwnThumbprint) }

    $Now = (Get-Date).ToUniversalTime()
    $Credentials = [System.Collections.Generic.List[object]]::new()
    $AddCredential = {
        param($Credential, $Type, $Thumbprint)
        $Flag = $Flags[[string]$Credential.keyId]
        $Credentials.Add([pscustomobject]@{
                keyId         = [string]$Credential.keyId
                displayName   = $Credential.displayName
                type          = $Type
                startDateTime = $Credential.startDateTime
                endDateTime   = $Credential.endDateTime
                hint          = $Credential.hint
                thumbprint    = $Thumbprint
                owner         = Get-CIPPSAMCredentialOwner -KeyId $Credential.keyId -DisplayName $Credential.displayName -Type $Type -Thumbprint $Thumbprint -OwnSecretKeyId $OwnSecretKeyId -OwnThumbprint $OwnThumbprint
                expired       = [bool]($Credential.endDateTime -and ([datetime]$Credential.endDateTime).ToUniversalTime() -lt $Now)
                # Credentials CIPP created itself are implicitly known.
                known         = [bool]($Flag.Label -or $Flag.Source)
                label         = $Flag.Label
                flaggedBy     = $Flag.FlaggedBy
                flaggedAt     = $Flag.FlaggedAt
                source        = $Flag.Source
                actor         = $Flag.Actor
                createdBy     = $Flag.CreatedBy
                createdAt     = $Flag.CreatedAt
            })
    }
    foreach ($Credential in @($App.passwordCredentials)) {
        if ($Credential) { & $AddCredential $Credential 'Secret' $null }
    }
    foreach ($Credential in @($App.keyCredentials | Where-Object { $_.type -eq 'AsymmetricX509Cert' })) {
        & $AddCredential $Credential 'Certificate' (Resolve-CIPPSAMCredentialThumbprint -Credential $Credential -KnownThumbprints $KnownThumbprints)
    }

    [pscustomobject]@{
        AppObjectId       = $App.id
        ApplicationId     = $ApplicationId
        OwnSecretKeyId    = $OwnSecretKeyId
        OwnThumbprint     = $OwnThumbprint
        StoredCertificate = $StoredCertificate
        KeyCredentials    = @($App.keyCredentials)
        Credentials       = $Credentials
    }
}
