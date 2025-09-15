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
            $Results.Add($Result)
            return $Results.ToArray()
        }

        # Prepare bulk requests for all DIDs
        $RemoveRequests = foreach ($DID in $UserDIDs) {
            @{
                id     = $DID.telephoneNumber
                method = 'POST'
                url    = "admin/teams/telephoneNumberManagement/numberAssignments/unassignNumber"
                body   = @{
                    telephoneNumber = $DID.telephoneNumber
                    numberType      = $DID.numberType
                }
            }
        }

        # Execute bulk request
        $RemoveResults = New-GraphBulkRequest -tenantid $TenantFilter -requests @($RemoveRequests)

        # Process results
        $RemoveResults | ForEach-Object {
            $PhoneNumber = $_.id

            if ($_.status -eq 204) {
                $SuccessResult = "Successfully removed Teams Phone DID: '$PhoneNumber' from: '$Username' - '$UserID'"
                Write-LogMessage -headers $Headers -API $APIName -message $SuccessResult -Sev 'Info' -tenant $TenantFilter
                $Results.Add($SuccessResult)
                $SuccessCount++
            } else {
                $ErrorMessage = if ($_.body.error.message) {
                    $_.body.error.message
                } else {
                    "HTTP Status: $($_.status)"
                }

                $ErrorResult = "Failed to remove Teams Phone DID: '$PhoneNumber' from: '$Username' - '$UserID'. Error: $ErrorMessage"
                Write-LogMessage -headers $Headers -API $APIName -message $ErrorResult -Sev 'Error' -tenant $TenantFilter
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
