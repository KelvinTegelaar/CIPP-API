function Get-CIPPOmaSettingDecryptedValue {
    <#
    .SYNOPSIS
    Decrypts encrypted OMA setting values from Intune device configurations

    .DESCRIPTION
    When Intune policies contain encrypted OMA settings (e.g., using Custom policy templates),
    the Graph API returns a placeholder value (PGEvPg==) instead of the actual value.
    This function detects encrypted OMA settings and retrieves their plaintext values
    using the getOmaSettingPlainTextValue Graph API endpoint.

    .PARAMETER DeviceConfiguration
    The device configuration object retrieved from Graph API that may contain encrypted OMA settings

    .PARAMETER DeviceConfigurationId
    The ID of the device configuration policy

    .PARAMETER TenantFilter
    The tenant ID to query

    .EXAMPLE
    $policy = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations/$id" -tenantid $tenant
    $decryptedPolicy = Get-CIPPOmaSettingDecryptedValue -DeviceConfiguration $policy -DeviceConfigurationId $id -TenantFilter $tenant

    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$DeviceConfiguration,

        [Parameter(Mandatory = $true)]
        [string]$DeviceConfigurationId,

        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        Write-Host "Checking for encrypted OMA settings in device configuration: $($DeviceConfiguration.displayName)"
        # Check if the device configuration has OMA settings
        if (-not $DeviceConfiguration.omaSettings -or $DeviceConfiguration.omaSettings.Count -eq 0) {
            Write-Verbose 'No OMA settings found in device configuration'
            return $DeviceConfiguration
        }

        $hasEncryptedSettings = $false

        # Iterate through each OMA setting to find encrypted values
        for ($i = 0; $i -lt $DeviceConfiguration.omaSettings.Count; $i++) {
            $omaSetting = $DeviceConfiguration.omaSettings[$i]

            # Check if this OMA setting has a secretReferenceValueId (indicates encryption)
            if ($omaSetting.secretReferenceValueId) {
                $hasEncryptedSettings = $true
                Write-Verbose "Found encrypted OMA setting: $($omaSetting.displayName) with secretReferenceValueId: $($omaSetting.secretReferenceValueId)"

                try {
                    # Call the Graph API to get the plaintext value
                    $plaintextUri = "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations('$DeviceConfigurationId')/getOmaSettingPlainTextValue(secretReferenceValueId='$($omaSetting.secretReferenceValueId)')"
                    Write-Verbose "Calling Graph API: $plaintextUri"

                    $plaintextResponse = New-GraphGetRequest -uri $plaintextUri -tenantid $TenantFilter

                    # The API returns the plaintext value in the 'value' property
                    if ($plaintextResponse) {
                        Write-Verbose "Successfully decrypted OMA setting: $($omaSetting.displayName)"
                        
                        # Check the OMA setting type to determine if we need to base64 encode the value
                        # omaSettingStringXml requires base64 encoded values (Edm.Binary)
                        # omaSettingString uses plaintext values
                        $omaType = $DeviceConfiguration.omaSettings[$i].'@odata.type'
                        
                        if ($omaType -eq '#microsoft.graph.omaSettingStringXml') {
                            # For StringXml type, the value must be base64 encoded
                            Write-Verbose "OMA setting type is StringXml, encoding value to base64"
                            $bytes = [System.Text.Encoding]::UTF8.GetBytes($plaintextResponse)
                            $DeviceConfiguration.omaSettings[$i].value = [System.Convert]::ToBase64String($bytes)
                        } else {
                            # For other types (String, Integer, Boolean, etc.), use the value as-is
                            Write-Verbose "OMA setting type is $omaType, using plaintext value"
                            $DeviceConfiguration.omaSettings[$i].value = $plaintextResponse
                        }

                        # Remove encryption-related properties as we now have the plaintext value
                        # This is important for when the policy is re-applied to another tenant
                        # Check if properties exist before attempting to remove them to avoid errors
                        if ($DeviceConfiguration.omaSettings[$i].PSObject.Properties['secretReferenceValueId']) {
                            $DeviceConfiguration.omaSettings[$i].PSObject.Properties.Remove('secretReferenceValueId')
                        }
                        if ($DeviceConfiguration.omaSettings[$i].PSObject.Properties['isEncrypted']) {
                            $DeviceConfiguration.omaSettings[$i].PSObject.Properties.Remove('isEncrypted')
                        }
                    } else {
                        Write-Warning "Failed to decrypt OMA setting: $($omaSetting.displayName) - No value returned from API"
                    }
                } catch {
                    Write-Warning "Error decrypting OMA setting '$($omaSetting.displayName)': $($_.Exception.Message)"
                    # Continue with other settings even if one fails
                }
            }
            # Also check for the placeholder value PGEvPg== (base64 encoded '<a/>')
            elseif ($omaSetting.value -eq 'PGEvPg==') {
                Write-Warning "Found placeholder value (PGEvPg==) for OMA setting '$($omaSetting.displayName)' but no secretReferenceValueId. This setting may not be decryptable."
            }
        }

        if (-not $hasEncryptedSettings) {
            Write-Verbose 'No encrypted OMA settings found in device configuration'
        }

        return $DeviceConfiguration

    } catch {
        Write-Error "Error processing OMA settings for device configuration: $($_.Exception.Message)"
        # Return the original configuration if there's an error
        return $DeviceConfiguration
    }
}
