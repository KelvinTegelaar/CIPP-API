function New-CIPPSSOApp {
    <#
    .SYNOPSIS
        Creates or updates the CIPP-SSO app registration for EasyAuth SSO migration.
    .DESCRIPTION
        Creates a new or updates an existing Entra ID app registration for CIPP-SSO with
        openid, profile, and email delegated permissions. If ExistingAppId is provided,
        looks up that specific app by clientId. If the app no longer exists in the tenant,
        creates a new one. Generates a client secret and returns the details needed to
        configure EasyAuth.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RedirectUri,

        [Parameter(Mandatory = $false)]
        [bool]$MultiTenant = $false,

        [Parameter(Mandatory = $false)]
        [string]$ExistingAppId
    )

    $AppDisplayName = 'CIPP-SSO'
    $CallbackUri = $RedirectUri.TrimEnd('/') + '/.auth/login/aad/callback'
    $SignInAudience = if ($MultiTenant) { 'AzureADMultipleOrgs' } else { 'AzureADMyOrg' }

    # Microsoft Graph resource ID and delegated permission GUIDs
    $GraphResourceId = '00000003-0000-0000-c000-000000000000'
    $Permissions = @(
        @{ id = '37f7f235-527c-4136-accd-4a02d197296e'; type = 'Scope' }  # openid
        @{ id = '14dad69e-099b-42c9-810b-d002981feec1'; type = 'Scope' }  # profile
        @{ id = '64a6cdd6-aab1-4aaf-94b8-3cc8405e90d0'; type = 'Scope' }  # email
    )

    # Look up existing app by stored AppId (not by name — supports multiple CIPP instances)
    $ExistingApp = $null
    if ($ExistingAppId) {
        try {
            $ExistingApp = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/applications(appId='$ExistingAppId')?`$select=id,appId,displayName,web" -NoAuthCheck $true -AsApp $true
            Write-Information "[SSO-App] Found existing app by AppId: $ExistingAppId"
        } catch {
            Write-Information "[SSO-App] Stored AppId $ExistingAppId not found in tenant — will create new app"
        }
    }

    $AppObjectId = $null
    $AppClientId = $null
    $State = $null

    if ($ExistingApp) {
        # Reuse existing app — patch redirect URIs and audience
        $AppObjectId = $ExistingApp.id
        $AppClientId = $ExistingApp.appId
        $State = 'updated'
        Write-Information "[SSO-App] Updating existing app: $AppClientId"

        $PatchBody = @{
            web                    = @{
                redirectUris          = @($CallbackUri)
                implicitGrantSettings = @{ enableIdTokenIssuance = $true }
            }
            signInAudience         = $SignInAudience
            requiredResourceAccess = @(
                @{
                    resourceAppId  = $GraphResourceId
                    resourceAccess = $Permissions
                }
            )
        } | ConvertTo-Json -Depth 10 -Compress

        New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/applications/$AppObjectId" -body $PatchBody -type PATCH -NoAuthCheck $true -AsApp $true
    } else {
        # Create new app registration
        $State = 'created'
        Write-Information "[SSO-App] Creating new app registration: $AppDisplayName"

        $CreateBody = @{
            displayName            = $AppDisplayName
            signInAudience         = $SignInAudience
            web                    = @{
                redirectUris          = @($CallbackUri)
                implicitGrantSettings = @{ enableIdTokenIssuance = $true }
            }
            requiredResourceAccess = @(
                @{
                    resourceAppId  = $GraphResourceId
                    resourceAccess = $Permissions
                }
            )
        } | ConvertTo-Json -Depth 10 -Compress

        $NewApp = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/v1.0/applications' -body $CreateBody -type POST -NoAuthCheck $true -AsApp $true
        $AppObjectId = $NewApp.id
        $AppClientId = $NewApp.appId
        Write-Information "[SSO-App] Created app: $AppClientId (objectId: $AppObjectId)"

        # Create service principal (idempotent — catch conflict)
        $Attempt = 0
        $SpnCreated = $false
        while ($Attempt -lt 3 -and -not $SpnCreated) {
            try {
                Start-Sleep -Seconds 2
                $SpnBody = @{ appId = $AppClientId } | ConvertTo-Json -Compress
                New-GraphPOSTRequest -uri 'https://graph.microsoft.com/v1.0/servicePrincipals' -body $SpnBody -type POST -NoAuthCheck $true -AsApp $true | Out-Null
                $SpnCreated = $true
                Write-Information "[SSO-App] Service principal created for $AppClientId"
            } catch {
                $Attempt++
                Write-Information "[SSO-App] SPN creation attempt $Attempt failed (may already exist): $($_.Exception.Message)"
            }
        }
    }

    # Handle app management policy exemption (same pattern as SAM setup)
    try {
        $PolicyStatus = Update-AppManagementPolicy -ApplicationId $AppClientId
        Write-Information "[SSO-App] Policy exemption: $($PolicyStatus.PolicyAction)"
    } catch {
        Write-Warning "[SSO-App] App management policy update failed (secret creation may still work): $($_.Exception.Message)"
    }

    # Create client secret with retry
    $SecretText = $null
    $SecretAttempt = 0
    $MaxSecretRetries = 5
    while ($SecretAttempt -lt $MaxSecretRetries -and -not $SecretText) {
        try {
            $PasswordBody = '{"passwordCredential":{"displayName":"CIPP-SSO-Secret"}}'
            $PasswordResult = New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/applications/$AppObjectId/addPassword" -body $PasswordBody -type POST -NoAuthCheck $true -AsApp $true
            $SecretText = $PasswordResult.secretText
            Write-Information "[SSO-App] Client secret created"
        } catch {
            $SecretAttempt++
            Write-Warning "[SSO-App] Secret creation attempt $SecretAttempt/$MaxSecretRetries failed: $($_.Exception.Message)"
            if ($SecretAttempt -lt $MaxSecretRetries) {
                $Delay = @(2, 5, 10, 15, 30)[$SecretAttempt - 1]
                Start-Sleep -Seconds $Delay
            }
        }
    }

    if (-not $SecretText) {
        throw "Failed to create client secret for $AppDisplayName after $MaxSecretRetries attempts"
    }

    return [PSCustomObject]@{
        AppId        = $AppClientId
        ObjectId     = $AppObjectId
        ClientSecret = $SecretText
        TenantId     = $env:TenantID
        DisplayName  = $AppDisplayName
        State        = $State
        MultiTenant  = $MultiTenant
    }
}
