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

    $BaseUri = 'https://graph.microsoft.com/v1.0/admin/teams/telephoneNumberManagement/numberAssignments'

    try {

        # Set Username to UserID if not provided
        if ([string]::IsNullOrEmpty($Username)) {
            $Username = $UserID
        }

        # Initialize collections for results
        $Results = [List[string]]::new()
        $SuccessCount = 0
        $ErrorCount = 0

        $TeamsPhoneDIDs = New-GraphGetRequest -uri $BaseUri -tenantid $TenantFilter

        if (-not $TeamsPhoneDIDs -or $TeamsPhoneDIDs.Count -eq 0) {
            $Result = 'No Teams Phone DIDs found in tenant'
            $Results.Add($Result)
            return $Results.ToArray()
        }

        # Filter DIDs assigned to the specific user
        $UserDIDs = @($TeamsPhoneDIDs | Where-Object { $_.assignmentTargetId -eq $UserID -and $_.assignmentStatus -ne 'unassigned' })

        if ($UserDIDs.Count -eq 0) {
            $Result = "No Teams Phone DIDs found assigned to user: '$Username' - '$UserID'"
            $Results.Add($Result)
            return $Results.ToArray()
        }

        # One POST per number: $batch fails with an IIS 'Request Too Long' page.
        foreach ($DID in $UserDIDs) {
            $PhoneNumber = $DID.telephoneNumber
            try {
                $Body = @{
                    telephoneNumber = $PhoneNumber
                    numberType      = Get-CippTeamsNumberType -NumberType $DID.numberType
                }
                $null = New-GraphPOSTRequest -uri "$BaseUri/unassignNumber" -tenantid $TenantFilter -body ($Body | ConvertTo-Json -Compress) -type POST

                $SuccessResult = "Successfully removed Teams Phone DID: '$PhoneNumber' from: '$Username' - '$UserID'"
                Write-LogMessage -headers $Headers -API $APIName -message $SuccessResult -Sev 'Info' -tenant $TenantFilter
                $Results.Add($SuccessResult)
                $SuccessCount++
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                $ErrorResult = "Failed to remove Teams Phone DID: '$PhoneNumber' from: '$Username' - '$UserID'. Error: $($ErrorMessage.NormalizedError)"
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
