function Invoke-ExecBECRemediate {
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


    $TenantFilter = $Request.Body.tenantFilter
    $SuspectUser = $Request.Body.userid
    $Username = $Request.Body.username
    Write-Host $TenantFilter
    Write-Host $SuspectUser

    $Results = try {
        $AllResults = [System.Collections.Generic.List[object]]::new()

        # Step 1: Reset Password
        $Step = 'Reset Password'
        try {
            $PasswordResult = Set-CIPPResetPassword -UserID $Username -tenantFilter $TenantFilter -APIName $APIName -Headers $Headers
            $AllResults.Add($PasswordResult)
        } catch {
            $AllResults.Add([pscustomobject]@{
                resultText = "Failed to reset password: $($_.Exception.Message)"
                state      = 'error'
            })
        }

        # Step 2: Disable Account
        $Step = 'Disable Account'
        try {
            $DisableResult = Set-CIPPSignInState -userid $Username -AccountEnabled $false -tenantFilter $TenantFilter -APIName $APIName -Headers $Headers
            $AllResults.Add([pscustomobject]@{
                resultText = $DisableResult
                state      = if ($DisableResult -like "*WARNING*") { 'warning' } else { 'success' }
            })
        } catch {
            $AllResults.Add([pscustomobject]@{
                resultText = "Failed to disable account: $($_.Exception.Message)"
                state      = 'error'
            })
        }

        # Step 3: Revoke Sessions
        $Step = 'Revoke Sessions'
        try {
            $SessionResult = Revoke-CIPPSessions -userid $SuspectUser -username $Username -Headers $Headers -APIName $APIName -tenantFilter $TenantFilter
            $AllResults.Add([pscustomobject]@{
                resultText = $SessionResult
                state      = if ($SessionResult -like "*Failed*") { 'error' } else { 'success' }
            })
        } catch {
            $AllResults.Add([pscustomobject]@{
                resultText = "Failed to revoke sessions: $($_.Exception.Message)"
                state      = 'error'
            })
        }

        # Step 4: Remove MFA methods
        $Step = 'Remove MFA methods'
        try {
            $MFAResult = Remove-CIPPUserMFA -UserPrincipalName $Username -TenantFilter $TenantFilter -Headers $Headers
            $AllResults.Add([pscustomobject]@{
                resultText = $MFAResult
                state      = if ($MFAResult -like "*No MFA methods*") { 'info' } elseif ($MFAResult -like "*Successfully*") { 'success' } else { 'error' }
            })
        } catch {
            $AllResults.Add([pscustomobject]@{
                resultText = "Failed to remove MFA methods: $($_.Exception.Message)"
                state      = 'error'
            })
        }

        # Step 5: Disable Inbox Rules
        $Step = 'Disable Inbox Rules'
        try {
            Write-LogMessage -headers $Headers -API $APIName -message "Starting inbox rules processing for user: $Username" -Sev 'Info' -tenant $TenantFilter
            $Rules = New-ExoRequest -anchor $Username -tenantid $TenantFilter -cmdlet 'Get-InboxRule' -cmdParams @{Mailbox = $Username; IncludeHidden = $true }
            Write-LogMessage -headers $Headers -API $APIName -message "Retrieved $(($Rules | Measure-Object).Count) total rules for $Username" -Sev 'Info' -tenant $TenantFilter
            $RuleDisabled = 0
            $RuleFailed = 0
            $DelegateRulesSkipped = 0
            $RuleMessages = [System.Collections.Generic.List[string]]::new()

            if (($Rules | Measure-Object).Count -eq 0) {
                # No rules exist at all
                $AllResults.Add([pscustomobject]@{
                    resultText = "No Inbox Rules found for $Username."
                    state      = 'info'
                })
            } else {
                # Rules exist, filter and process them
                $ProcessableRules = $Rules | Where-Object {
                    $_.Name -ne 'Junk E-Mail Rule' -and
                    $_.Name -notlike 'Microsoft.Exchange.OOF.*'
                }

                if (($ProcessableRules | Measure-Object).Count -eq 0) {
                    # Rules exist but none are processable after filtering
                    $SystemRulesCount = ($Rules | Measure-Object).Count - $DelegateRulesSkipped
                    if ($SystemRulesCount -gt 0) {
                        $AllResults.Add([pscustomobject]@{
                            resultText = "Found $(($Rules | Measure-Object).Count) inbox rules for $Username, but none require disabling (only system rules found)."
                            state      = 'info'
                        })
                    }
                } else {
                    # Process the filterable rules
                    $ProcessableRules | ForEach-Object {
                        $CurrentRule = $_
                        Write-LogMessage -headers $Headers -API $APIName -message "Processing rule: Name='$($CurrentRule.Name)', Identity='$($CurrentRule.Identity)'" -Sev 'Info' -tenant $TenantFilter

                        try {
                            Set-CIPPMailboxRule -Username $Username -TenantFilter $TenantFilter -RuleId $CurrentRule.Identity -RuleName $CurrentRule.Name -Disable -APIName $APIName -Headers $Headers

                            Write-LogMessage -headers $Headers -API $APIName -message "Successfully disabled rule: $($CurrentRule.Name)" -Sev 'Info' -tenant $TenantFilter
                            $RuleDisabled++
                        } catch {
                            # Check if this is a system delegate rule, if so we can ignore the error
                            if ($CurrentRule.Name -match '^Delegate Rule -\d+$') {
                                Write-LogMessage -headers $Headers -API $APIName -message "Skipping delegate rule '$($CurrentRule.Name)' - unable to disable (expected behavior)" -Sev 'Info' -tenant $TenantFilter
                                $DelegateRulesSkipped++
                            } else {
                                # Handle as normal error
                                $ErrorMsg = "Could not disable rule '$($CurrentRule.Name)': $($_.Exception.Message)"
                                Write-LogMessage -headers $Headers -API $APIName -message $ErrorMsg -Sev 'Error' -tenant $TenantFilter
                                $RuleMessages.Add($ErrorMsg)
                                $RuleFailed++
                            }
                        }
                    }

                    # Report results
                    if ($RuleDisabled -gt 0) {
                        $AllResults.Add([pscustomobject]@{
                            resultText = "Successfully disabled $RuleDisabled inbox rules for $Username"
                            state      = 'success'
                        })
                    } elseif ($DelegateRulesSkipped -gt 0 -and $RuleDisabled -eq 0 -and $RuleFailed -eq 0) {
                        # Only system rules were found, report as no processable rules
                        $AllResults.Add([pscustomobject]@{
                            resultText = "No processable inbox rules found for $Username"
                            state      = 'info'
                        })
                    }

                    if ($RuleFailed -gt 0) {
                        $AllResults.Add([pscustomobject]@{
                            resultText = "Failed to process $RuleFailed inbox rules for $Username"
                            state      = 'warning'
                        })

                        # Add individual rule failure messages as objects
                        foreach ($RuleMessage in $RuleMessages) {
                            $AllResults.Add([pscustomobject]@{
                                resultText = $RuleMessage
                                state      = 'error'
                            })
                        }
                    }
                }
            }

            $TotalProcessed = $RuleDisabled + $RuleFailed + $DelegateRulesSkipped
            Write-LogMessage -headers $Headers -API $APIName -message "Completed inbox rules processing for $Username. Total rules: $(($Rules | Measure-Object).Count), Processed: $TotalProcessed, Disabled: $RuleDisabled, Failed: $RuleFailed, Delegate rules skipped: $DelegateRulesSkipped" -Sev 'Info' -tenant $TenantFilter

        } catch {
            $ErrorMsg = "Failed to process inbox rules: $($_.Exception.Message)"
            Write-LogMessage -headers $Headers -API $APIName -message $ErrorMsg -Sev 'Error' -tenant $TenantFilter
            $AllResults.Add([pscustomobject]@{
                resultText = $ErrorMsg
                state      = 'error'
            })
        }

        $StatusCode = [HttpStatusCode]::OK
        Write-LogMessage -API 'BECRemediate' -tenant $TenantFilter -message "Executed Remediation for $Username" -sev 'Info' -LogData @($AllResults)

        # Return the results array
        $AllResults.ToArray()

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $ErrorList = [System.Collections.Generic.List[object]]::new()
        $ErrorList.Add([pscustomobject]@{
            resultText = "Failed to execute remediation at step '$Step'. $($ErrorMessage.NormalizedError)"
            state      = 'error'
        })
        Write-LogMessage -API 'BECRemediate' -tenant $TenantFilter -message "Executed Remediation for $Username failed at the $Step step" -sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError

        # Return the error array
        $ErrorList.ToArray()
    }

    # Create the final response structure
    $ResponseBody = [pscustomobject]@{'Results' = @($Results) }

    # Associate values to output bindings
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $ResponseBody
        })

}
