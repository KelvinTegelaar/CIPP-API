function Repair-CippApiIdentifierUri {
    <#
    .SYNOPSIS
        Validates and repairs the Application ID URI (api://{appId}) for a CIPP API client
    .DESCRIPTION
        Checks if an application has the correct identifier URI set (api://{appId}) and fixes it if missing or incorrect.
        This is required for client_credentials (app-only) authentication to work properly with EasyAuth.
    .PARAMETER AppId
        The Application (Client) ID of the app to check/repair
    .PARAMETER ApplicationObjectId
        Optional. The object ID of the application. If not provided, will be looked up.
    .EXAMPLE
        Repair-CippApiIdentifierUri -AppId '12345678-1234-1234-1234-123456789012'
    .OUTPUTS
        PSCustomObject with properties:
        - Fixed: boolean indicating if a fix was applied
        - PreviousUri: the previous identifier URI (if any)
        - CurrentUri: the current/fixed identifier URI
        - Message: description of what happened
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppId,

        [Parameter(Mandatory = $false)]
        [string]$ApplicationObjectId
    )

    try {
        # Get the application details
        $App = if ($ApplicationObjectId) {
            New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/applications/$ApplicationObjectId" -NoAuthCheck $true -AsApp $true -ErrorAction Stop
        } else {
            $Apps = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/applications?`$filter=appId eq '$AppId'&`$select=id,appId,identifierUris" -NoAuthCheck $true -AsApp $true -ErrorAction Stop
            if ($Apps -is [array] -and $Apps.Count -gt 0) {
                $Apps[0]
            } elseif ($Apps.id) {
                $Apps
            } else {
                throw "Application with AppId '$AppId' not found"
            }
        }

        $DesiredUri = "api://$($App.appId)"
        $CurrentUris = @($App.identifierUris)

        Write-Information "Application '$($App.appId)': Current identifier URIs: $($CurrentUris -join ', ')"

        # Check if the desired URI is already present
        if ($CurrentUris -contains $DesiredUri) {
            return [PSCustomObject]@{
                Fixed       = $false
                PreviousUri = $CurrentUris -join ', '
                CurrentUri  = $DesiredUri
                Message     = "Identifier URI '$DesiredUri' already correctly configured"
            }
        }

        # Need to add/fix the URI
        Write-Information "Identifier URI missing or incorrect. Setting to '$DesiredUri'"

        if ($PSCmdlet.ShouldProcess($App.appId, "Set identifier URI to '$DesiredUri'")) {
            $PatchBody = @{
                identifierUris = @($DesiredUri)
            }

            $Retries = 0
            $MaxRetries = 3
            $Success = $false

            while (-not $Success -and $Retries -lt $MaxRetries) {
                try {
                    $Retries++
                    New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/applications/$($App.id)" -AsApp $true -NoAuthCheck $true -type PATCH -body $PatchBody -maxRetries 1 | Out-Null
                    $Success = $true
                    Write-Information "Successfully set identifier URI on attempt $Retries"
                } catch {
                    $ErrorMsg = $_.Exception.Message
                    Write-Warning "Attempt $Retries to set identifier URI failed: $ErrorMsg"

                    if ($Retries -lt $MaxRetries) {
                        Start-Sleep -Seconds 2
                    } else {
                        throw "Failed to set identifier URI after $MaxRetries attempts: $ErrorMsg"
                    }
                }
            }

            return [PSCustomObject]@{
                Fixed       = $true
                PreviousUri = $CurrentUris -join ', '
                CurrentUri  = $DesiredUri
                Message     = "Identifier URI successfully set to '$DesiredUri'"
            }
        }
    } catch {
        Write-Warning "Failed to repair identifier URI for AppId '$AppId': $($_.Exception.Message)"
        throw
    }
}
