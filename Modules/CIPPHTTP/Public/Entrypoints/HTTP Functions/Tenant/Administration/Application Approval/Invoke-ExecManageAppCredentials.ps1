function Invoke-ExecManageAppCredentials {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Application.ReadWrite
    .DESCRIPTION
        Adds, removes and rotates the credentials of an app registration or service principal: client secrets
        (CredentialType password) and certificates (key, remove only). Federated credentials (CredentialType
        federated, app registrations only) let tokens from another identity provider sign in as the app without a
        secret: Add builds one from a Scenario (GitHub, Kubernetes, ManagedIdentity or Other) and Remove deletes the
        one whose id is KeyId.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    $TenantFilter = $Request.Body.tenantFilter
    $Action = $Request.Body.Action
    $AppType = $Request.Body.AppType           # applications | servicePrincipals
    $CredentialType = $Request.Body.CredentialType # password | key
    $KeyId = $Request.Body.KeyId
    $AppId = $Request.Body.AppId
    $Id = $Request.Body.Id
    $DisplayName = $Request.Body.DisplayName
    $EndDateTime = $Request.Body.EndDateTime
    $ExpiryMonths = $Request.Body.ExpiryMonths.value ?? $Request.Body.ExpiryMonths
    $ExpiryDate = $Request.Body.ExpiryDate
    $AppRef = $Id ?? $AppId

    $IdPath = if ($Id) { "/$Id" } else { "(appId='$AppId')" }
    $Uri = "https://graph.microsoft.com/beta/$AppType$IdPath"

    # Max credential end date allowed by the tenant default app management policy's passwordLifetime
    # restriction, or $null when not enforced/readable. Custom per-app policies aren't read here.
    function Get-PasswordPolicyMaxEnd {
        param([datetime]$From)
        try {
            $Policy = New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/policies/defaultAppManagementPolicy' -tenantid $TenantFilter -AsApp $true
            $Lifetime = $Policy.applicationRestrictions.passwordCredentials | Where-Object { $_.restrictionType -eq 'passwordLifetime' }
            if ($Lifetime -and -not ($Lifetime.state -eq 'disabled' -or $null -eq $Lifetime.state) -and $Lifetime.maxLifetime) {
                return $From.Add([System.Xml.XmlConvert]::ToTimeSpan($Lifetime.maxLifetime))
            }
        } catch {
            Write-LogMessage -API $APIName -tenant $TenantFilter -headers $Headers -message "Could not read app management policy for expiry clamping: $($_.Exception.Message)" -sev Debug
        }
        return $null
    }

    # The federated credential to add, from the scenario fields the dialog posts. Returns an error string when the
    # input is incomplete or invalid.
    function Get-FederatedCredentialBody {
        param($Body)
        $Value = { param($Field) "$($Body.$Field.value ?? $Body.$Field)".Trim() }
        $Name = & $Value 'Name'
        if ($Name.Length -lt 1 -or $Name.Length -gt 120) { return 'A name of 1 to 120 characters is required' }
        $Scenario = & $Value 'Scenario'
        $Segment = '^[A-Za-z0-9_.-]+$'
        switch ($Scenario) {
            'GitHub' {
                $Org = & $Value 'GitHubOrganization'
                $Repo = & $Value 'GitHubRepository'
                $EntityType = & $Value 'GitHubEntityType'
                $Entity = & $Value 'GitHubEntityValue'
                if ($Org -notmatch $Segment -or $Repo -notmatch $Segment) { return 'A GitHub organization and repository are required' }
                if ($EntityType -notin @('Environment', 'Branch', 'Tag', 'PullRequest')) { return 'GitHubEntityType must be Environment, Branch, Tag or PullRequest' }
                if ($EntityType -ne 'PullRequest' -and -not $Entity) { return "The GitHub $($EntityType.ToLowerInvariant()) name is required" }
                $Issuer = 'https://token.actions.githubusercontent.com'
                $Subject = switch ($EntityType) {
                    'Environment' { "repo:$($Org)/$($Repo):environment:$Entity" }
                    'Branch' { "repo:$($Org)/$($Repo):ref:refs/heads/$Entity" }
                    'Tag' { "repo:$($Org)/$($Repo):ref:refs/tags/$Entity" }
                    'PullRequest' { "repo:$($Org)/$($Repo):pull_request" }
                }
            }
            'Kubernetes' {
                $Issuer = & $Value 'KubernetesIssuer'
                $Namespace = & $Value 'KubernetesNamespace'
                $ServiceAccount = & $Value 'KubernetesServiceAccount'
                if ($Namespace -notmatch $Segment -or $ServiceAccount -notmatch $Segment) { return 'A Kubernetes namespace and service account are required' }
                $Subject = "system:serviceaccount:$($Namespace):$ServiceAccount"
            }
            'ManagedIdentity' {
                $Identity = & $Value 'ManagedIdentity'
                if ($Identity -notmatch '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') { return 'Select a managed identity' }
                $TenantId = @(Get-Tenants -TenantFilter $TenantFilter)[0].customerId
                if (-not $TenantId) { return 'The tenant ID could not be found' }
                $Issuer = "https://login.microsoftonline.com/$TenantId/v2.0"
                $Subject = $Identity
            }
            'Other' {
                $Issuer = & $Value 'Issuer'
                $Subject = & $Value 'Subject'
                if (-not $Subject) { return 'A subject is required' }
            }
            default { return 'Scenario must be GitHub, Kubernetes, ManagedIdentity or Other' }
        }
        if ($Issuer -notmatch '^https://[^\s/]+') { return 'The issuer must be an https URL' }
        $Audience = & $Value 'Audience'
        $Credential = @{
            name      = $Name
            issuer    = $Issuer
            subject   = $Subject
            audiences = @($(if ($Audience) { $Audience } else { 'api://AzureADTokenExchange' }))
        }
        $Description = & $Value 'Description'
        if ($Description) { $Credential.description = $Description }
        $Credential
    }

    try {
        if ($CredentialType -eq 'federated' -and $AppType -ne 'applications') {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = @{ Results = @{ resultText = 'Federated credentials exist only on app registrations (AppType applications).'; state = 'error' } }
                })
        }
        $Results = switch ($Action) {
            'Remove' {
                if ($CredentialType -eq 'federated') {
                    if ("$KeyId" -notmatch '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') {
                        @{ resultText = 'KeyId must be the id of the federated credential to remove.'; state = 'error' }
                    } else {
                        $Label = if ($DisplayName) { "'$DisplayName'" } else { $KeyId }
                        $null = New-GraphPOSTRequest -Uri "$Uri/federatedIdentityCredentials/$KeyId" -Type 'DELETE' -Body '{}' -tenantid $TenantFilter
                        Write-LogMessage -API $APIName -tenant $TenantFilter -headers $Headers -message "Removed federated credential $Label ($KeyId) from $AppType $AppRef" -sev Info
                        @{ resultText = "Removed federated credential $Label. Tokens it trusted can no longer sign in as the app."; state = 'success' }
                    }
                } elseif ($CredentialType -eq 'password') {
                    $null = New-GraphPOSTRequest -Uri "$Uri/removePassword" -Body (@{ keyId = $KeyId } | ConvertTo-Json) -tenantid $TenantFilter
                    Write-LogMessage -API $APIName -tenant $TenantFilter -headers $Headers -message "Removed password credential $KeyId from $AppType $AppRef" -sev Info
                    @{ resultText = "Successfully removed password credential $KeyId"; state = 'success' }
                } else {
                    # Certificates can't use removeKey without a proof JWT, so PATCH the array instead
                    $Current = New-GraphGetRequest -Uri $Uri -tenantid $TenantFilter
                    $Updated = @($Current.keyCredentials | Where-Object { $_.keyId -ne $KeyId })
                    $null = New-GraphPOSTRequest -Uri $Uri -Type 'PATCH' -Body (@{ keyCredentials = $Updated } | ConvertTo-Json -Depth 10) -tenantid $TenantFilter
                    Write-LogMessage -API $APIName -tenant $TenantFilter -headers $Headers -message "Removed key credential $KeyId from $AppType $AppRef" -sev Info
                    @{ resultText = "Successfully removed key credential $KeyId"; state = 'success' }
                }
            }
            'Add' {
                # Only client secret (password) addition is implemented here. Adding a certificate means
                # PATCHing keyCredentials with an uploaded public-key cert - not built yet; use Entra.
                if ($CredentialType -eq 'federated') {
                    $Federated = Get-FederatedCredentialBody -Body $Request.Body
                    if ($Federated -is [string]) {
                        @{ resultText = $Federated; state = 'error' }
                    } else {
                        $null = New-GraphPOSTRequest -Uri "$Uri/federatedIdentityCredentials" -Body (ConvertTo-Json -InputObject $Federated -Depth 5 -Compress) -tenantid $TenantFilter
                        Write-LogMessage -API $APIName -tenant $TenantFilter -headers $Headers -message "Added federated credential '$($Federated.name)' (issuer $($Federated.issuer), subject $($Federated.subject)) to $AppType $AppRef" -sev Info
                        @{ resultText = "Added federated credential '$($Federated.name)': tokens from $($Federated.issuer) for $($Federated.subject) now sign in as the app."; state = 'success' }
                    }
                } elseif ($CredentialType -ne 'password') {
                    @{ resultText = 'Adding certificate credentials is not supported here yet. Upload the certificate in Entra instead.'; state = 'error' }
                } else {
                    $PasswordCredential = @{
                        displayName = if ([string]::IsNullOrWhiteSpace($DisplayName)) { 'CIPP-Generated Secret' } else { $DisplayName }
                    }

                    $Now = (Get-Date).ToUniversalTime()
                    if ($EndDateTime) {
                        $RequestedEnd = ([System.DateTimeOffset]$EndDateTime).UtcDateTime
                    } elseif ($ExpiryDate) {
                        $RequestedEnd = [System.DateTimeOffset]::FromUnixTimeSeconds([long]$ExpiryDate).UtcDateTime
                    } else {
                        $Months = if ($ExpiryMonths -as [int]) { [int]$ExpiryMonths } else { 12 }
                        $RequestedEnd = $Now.AddMonths($Months)
                    }

                    # Clamp the expiry to the tenant policy maximum so the add isn't rejected outright.
                    $ClampNote = ''
                    $MaxAllowedEnd = Get-PasswordPolicyMaxEnd -From $Now
                    if ($MaxAllowedEnd -and $RequestedEnd -gt $MaxAllowedEnd) {
                        $RequestedEnd = $MaxAllowedEnd
                        $ClampNote = " Expiry was reduced to the tenant policy maximum of $([math]::Round(($MaxAllowedEnd - $Now).TotalDays)) day(s)."
                    }

                    $PasswordCredential.endDateTime = $RequestedEnd.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')

                    $NewSecret = New-GraphPOSTRequest -Uri "$Uri/addPassword" -Body (@{ passwordCredential = $PasswordCredential } | ConvertTo-Json -Depth 10) -tenantid $TenantFilter
                    Write-LogMessage -API $APIName -tenant $TenantFilter -headers $Headers -message "Added password credential '$($PasswordCredential.displayName)' (keyId $($NewSecret.keyId)) to $AppType $AppRef" -sev Info
                    @{
                        resultText = "Client secret '$($PasswordCredential.displayName)' created for the app registration. Use the Copy to Clipboard button to retrieve the secret.$ClampNote"
                        copyField  = $NewSecret.secretText
                        state      = 'success'
                    }
                }
            }
            'Rotate' {
                # Rotate a client secret: add a replacement with the same display name, then remove the
                # original. Add first so a failure leaves the existing secret intact.
                if ($CredentialType -ne 'password') {
                    @{ resultText = 'Rotation is only supported for client secrets.'; state = 'error' }
                } elseif (-not $KeyId) {
                    @{ resultText = 'KeyId is required to rotate a secret.'; state = 'error' }
                } else {
                    $App = New-GraphGetRequest -Uri $Uri -tenantid $TenantFilter
                    $OldCred = $App.passwordCredentials | Where-Object { $_.keyId -eq $KeyId }
                    if (-not $OldCred) {
                        @{ resultText = "Secret $KeyId was not found on this application."; state = 'error' }
                    } else {
                        $Name = if ([string]::IsNullOrWhiteSpace($OldCred.displayName)) { 'CIPP-Generated Secret' } else { $OldCred.displayName }

                        $Now = (Get-Date).ToUniversalTime()
                        $RequestedEnd = $Now.AddMonths(12)
                        $ClampNote = ''
                        $MaxAllowedEnd = Get-PasswordPolicyMaxEnd -From $Now
                        if ($MaxAllowedEnd -and $RequestedEnd -gt $MaxAllowedEnd) {
                            $RequestedEnd = $MaxAllowedEnd
                            $ClampNote = " New secret expiry was set to the tenant policy maximum of $([math]::Round(($MaxAllowedEnd - $Now).TotalDays)) day(s)."
                        }

                        $NewCredential = @{
                            displayName = $Name
                            endDateTime = $RequestedEnd.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
                        }
                        $NewSecret = New-GraphPOSTRequest -Uri "$Uri/addPassword" -Body (@{ passwordCredential = $NewCredential } | ConvertTo-Json -Depth 10) -tenantid $TenantFilter

                        # Remove the old secret; if that fails, keep the new one and tell the caller.
                        $RemoveNote = ''
                        try {
                            $null = New-GraphPOSTRequest -Uri "$Uri/removePassword" -Body (@{ keyId = $KeyId } | ConvertTo-Json) -tenantid $TenantFilter
                        } catch {
                            $RemoveNote = ' The new secret was created, but the old one could not be removed - remove it manually.'
                        }

                        Write-LogMessage -API $APIName -tenant $TenantFilter -headers $Headers -message "Rotated password credential '$Name' on $AppType $AppRef (old keyId $KeyId, new keyId $($NewSecret.keyId))" -sev Info
                        @{
                            resultText = "Secret '$Name' rotated. Use the Copy to Clipboard button to retrieve the new secret.$ClampNote$RemoveNote"
                            copyField  = $NewSecret.secretText
                            state      = 'success'
                        }
                    }
                }
            }
            default {
                @{ resultText = "Unknown action: $Action"; state = 'error' }
            }
        }

        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @{ Results = $Results }
            })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $APIName -tenant $TenantFilter -headers $Headers -message "Failed to $Action credential: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::InternalServerError
                Body       = @{ Results = @{ resultText = "Failed to $Action credential: $($ErrorMessage.NormalizedError)"; state = 'error' } }
            })
    }
}
