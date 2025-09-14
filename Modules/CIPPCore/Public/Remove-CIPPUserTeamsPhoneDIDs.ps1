using namespace System.Net
using namespace System.Collections.Generic

function Remove-CIPPUserTeamsPhoneDIDs {
    [CmdletBinding()]
    param (
        $Headers,
        [parameter(Mandatory = $true)]
        [string]$UserID,
        [string]$Username,
        $APIName = 'Remove User Teams Phone DIDs',
        [parameter(Mandatory = $true)]
        $TenantFilter
    )

    try {

        # Set Username to UserID if not provided
        if ([string]::IsNullOrEmpty($Username)) {
            $Username = $UserID
        }

        # Initialize collections for results
        $Results = [List[string]]::new()
        $SuccessCount = 0
        $ErrorCount = 0

        # Get all tenant DIDs
        $TeamsPhoneDIDs = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/admin/teams/telephoneNumberManagement/numberAssignments" -tenant $TenantFilter

        if (-not $TeamsPhoneDIDs -or $TeamsPhoneDIDs.Count -eq 0) {
            $Result = "No Teams Phone DIDs found in tenant"
            $Results.Add($Result)
            return $Results.ToArray()
        }

        # Filter DIDs assigned to the specific user
        $UserDIDs = $TeamsPhoneDIDs | Where-Object { $_.assignmentTargetId -eq $UserID -and $_.assignmentStatus -ne 'unassigned' }

        if (-not $UserDIDs -or $UserDIDs.Count -eq 0) {
            $Result = "No Teams Phone DIDs found assigned to user: '$Username' - '$UserID'"
            Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Info' -tenant $TenantFilter
            $Results.Add($Result)
            return $Results.ToArray()
        }

        Write-LogMessage -headers $Headers -API $APIName -message "Found $($UserDIDs.Count) DIDs assigned to user: '$Username'" -Sev 'Info' -tenant $TenantFilter

        # Process each DID assigned to the user
        foreach ($DID in $UserDIDs) {
            try {
                $PhoneNumber = $DID.telephoneNumber
                $NumberType = $DID.numberType

                # Prepare the request body for unassigning the number
                $RequestBody = @{
                    telephoneNumber = $PhoneNumber
                    numberType = $NumberType
                } | ConvertTo-Json -Depth 3

                # Make the API call to unassign the number
                $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/admin/teams/telephoneNumberManagement/numberAssignments/unassignNumber" -type POST -body $RequestBody -contentType 'application/json' -tenant $TenantFilter

                $SuccessResult = "Successfully removed Teams Phone DID: '$PhoneNumber' from: '$Username' - '$UserID'"
                Write-LogMessage -headers $Headers -API $APIName -message $SuccessResult -Sev 'Info' -tenant $TenantFilter
                $Results.Add($SuccessResult)
                $SuccessCount++

            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                $ErrorResult = "Failed to remove Teams Phone DID: '$($DID.telephoneNumber)' from: '$Username' - '$UserID'. Error: $($ErrorMessage.NormalizedError)"
                Write-LogMessage -headers $Headers -API $APIName -message $ErrorResult -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
                $Results.Add($ErrorResult)
                $ErrorCount++
            }
        }

        # Add summary result
        $SummaryResult = "Completed processing $($UserDIDs.Count) DIDs for user '$Username': $SuccessCount successful, $ErrorCount failed"
        Write-LogMessage -headers $Headers -API $APIName -message $SummaryResult -Sev 'Info' -tenant $TenantFilter
        $Results.Add($SummaryResult)

        return $Results.ToArray()

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to process Teams Phone DIDs removal for: '$Username' - '$UserID'. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        throw $Result
    }
}
