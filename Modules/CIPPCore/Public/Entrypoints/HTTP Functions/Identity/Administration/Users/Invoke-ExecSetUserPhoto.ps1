function Invoke-ExecSetUserPhoto {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $tenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $userId = $Request.Query.userId ?? $Request.Body.userId
    $action = $Request.Query.action ?? $Request.Body.action
    $photoData = $Request.Body.photoData

    $Results = [System.Collections.Generic.List[object]]::new()

    try {
        if ([string]::IsNullOrWhiteSpace($userId)) {
            throw 'User ID is required'
        }

        if ($action -eq 'remove') {
            # Remove the user's profile picture
            try {
                $null = New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/users/$userId/photo/`$value" -tenantid $tenantFilter -type DELETE -NoAuthCheck $true
                $Results.Add('Successfully removed user profile picture.')
                Write-LogMessage -API $APIName -tenant $tenantFilter -headers $Headers -message "Removed profile picture for user $userId" -Sev Info
            } catch {
                # Check if the error is because there's no photo
                if ($_.Exception.Message -like '*does not exist*' -or $_.Exception.Message -like '*ResourceNotFound*') {
                    $Results.Add('User does not have a profile picture to remove.')
                    Write-LogMessage -API $APIName -tenant $tenantFilter -headers $Headers -message "No profile picture found for user $userId" -Sev Info
                } else {
                    throw $_
                }
            }
        } elseif ($action -eq 'set') {
            # Set the user's profile picture
            if ([string]::IsNullOrWhiteSpace($photoData)) {
                throw 'Photo data is required when setting a profile picture'
            }

            # Convert base64 string to byte array
            # The photoData should be in format: data:image/jpeg;base64,/9j/4AAQSkZJRg...
            # We need to strip the data URL prefix if present
            $base64Data = $photoData
            if ($photoData -match '^data:image/[^;]+;base64,(.+)$') {
                $base64Data = $Matches[1]
            }

            try {
                $photoBytes = [Convert]::FromBase64String($base64Data)
            } catch {
                throw "Invalid base64 photo data: $($_.Exception.Message)"
            }

            # Validate image size (Microsoft Graph has a 4MB limit)
            $maxSizeBytes = 4 * 1024 * 1024 # 4MB
            if ($photoBytes.Length -gt $maxSizeBytes) {
                throw "Photo size exceeds 4MB limit. Current size: $([math]::Round($photoBytes.Length / 1MB, 2))MB"
            }

            # Upload the photo using Graph API
            $null = New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/users/$userId/photo/`$value" -tenantid $tenantFilter -type PATCH -body $photoBytes -ContentType 'image/jpeg' -NoAuthCheck $true

            $Results.Add('Successfully set user profile picture.')
            Write-LogMessage -API $APIName -tenant $tenantFilter -headers $Headers -message "Set profile picture for user $userId" -Sev Info
        } else {
            throw "Invalid action. Must be 'set' or 'remove'"
        }

        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @{
                    'Results' = @($Results)
                }
            })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $APIName -tenant $tenantFilter -headers $Headers -message "Failed to $action user profile picture. Error: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{
                    'Results' = @("Failed to $action user profile picture: $($ErrorMessage.NormalizedError)")
                }
            })
    }
}
