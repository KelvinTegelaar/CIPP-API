# Pester tests for Resolve-CippExoBulkResult.
#
# This is the correlation step between what New-ExoBulkRequest returns and the operations the
# caller submitted. Getting it wrong is not a cosmetic problem: the failure mode it replaced
# reported rejected Exchange writes to the operator as "Success", so nobody went looking for the
# change that never happened. That was found against a live tenant, not in review.
#
# The shapes asserted here are the ones New-ExoBulkRequest actually produces:
#
#   error, message in details : @{ error = <details.message>; target = <details.target> }
#   error, message at top     : @{ error = <error.message>;   target = <details.target> }  <- target is null
#   success, cmdlet output    : the cmdlet's own objects, tagged with OperationGuid if supplied
#   success, no output        : @{ Success = $true; OperationGuid = ... } if a guid was supplied,
#                               otherwise nothing at all is emitted for that operation
#
# The last one is why "found no result for this operation" cannot mean failure, and the null
# target is why matching on target cannot be the primary mechanism.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Resolve-CippExoBulkResult.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Resolve-CippExoBulkResult.ps1 under Modules/' }

    . $FunctionPath

    function New-Operation {
        param([string]$Message, [string]$Target, [string]$OperationGuid)
        $Operation = @{ message = $Message; target = $Target }
        if ($OperationGuid) { $Operation.OperationGuid = $OperationGuid }
        return $Operation
    }

    # An error record exactly as New-ExoBulkRequest emits it.
    function New-ExoError {
        param([string]$Message, [string]$Target, [string]$OperationGuid)
        $Record = [pscustomobject]@{ error = $Message; target = $Target }
        if ($OperationGuid) { $Record | Add-Member -NotePropertyName OperationGuid -NotePropertyValue $OperationGuid }
        return $Record
    }

    # The synthesised success record New-ExoBulkRequest emits for a cmdlet that returns nothing.
    function New-ExoSuccess {
        param([string]$OperationGuid)
        [pscustomobject]@{ Success = $true; OperationGuid = $OperationGuid }
    }
}

Describe 'Resolve-CippExoBulkResult' {
    Context 'A batch that fully succeeded' {
        It 'reports success when Exchange returned nothing at all' {
            # Add-/Remove-DistributionGroupMember and Set-DistributionGroup produce no output, so a
            # completely successful batch comes back empty.
            $Operations = @(
                New-Operation -Message 'Added one' -Target 'one@contoso.com' -OperationGuid 'guid-1'
                New-Operation -Message 'Added two' -Target 'two@contoso.com' -OperationGuid 'guid-2'
            )

            $Result = @(Resolve-CippExoBulkResult -Response @() -Operations $Operations)

            $Result.Count | Should -Be 2
            $Result[0].Success | Should -BeTrue
            $Result[1].Success | Should -BeTrue
            $Result[0].ErrorMessage | Should -BeNullOrEmpty
            $Result[1].ErrorMessage | Should -BeNullOrEmpty
        }

        It 'reports success when Exchange returned the synthesised success records' {
            $Operations = @(New-Operation -Message 'Added one' -Target 'one@contoso.com' -OperationGuid 'guid-1')
            $Response = @(New-ExoSuccess -OperationGuid 'guid-1')

            $Result = @(Resolve-CippExoBulkResult -Response $Response -Operations $Operations)

            $Result[0].Success | Should -BeTrue
        }

        It 'reports success when the cmdlet returned its own objects' {
            $Operations = @(New-Operation -Message 'Got mailbox' -Target 'one@contoso.com' -OperationGuid 'guid-1')
            $Response = @([pscustomobject]@{ DisplayName = 'One'; OperationGuid = 'guid-1' })

            $Result = @(Resolve-CippExoBulkResult -Response $Response -Operations $Operations)

            $Result[0].Success | Should -BeTrue
        }

        It 'returns one result per operation, in the order they were submitted' {
            $Operations = @(
                New-Operation -Message 'first' -Target 'a' -OperationGuid 'guid-1'
                New-Operation -Message 'second' -Target 'b' -OperationGuid 'guid-2'
                New-Operation -Message 'third' -Target 'c' -OperationGuid 'guid-3'
            )

            $Result = @(Resolve-CippExoBulkResult -Response @() -Operations $Operations)

            $Result.Operation.message | Should -Be @('first', 'second', 'third')
        }
    }

    Context 'Attributing a failure to the operation that caused it' {
        It 'fails only the operation whose guid Exchange echoed back' {
            $Operations = @(
                New-Operation -Message 'Added one' -Target 'one@contoso.com' -OperationGuid 'guid-1'
                New-Operation -Message 'Added two' -Target 'two@contoso.com' -OperationGuid 'guid-2'
            )
            $Response = @(New-ExoError -Message 'The recipient could not be found.' -Target 'one@contoso.com' -OperationGuid 'guid-1')

            $Result = @(Resolve-CippExoBulkResult -Response $Response -Operations $Operations)

            $Result[0].Success | Should -BeFalse
            $Result[0].ErrorMessage | Should -Be 'The recipient could not be found.'
            $Result[1].Success | Should -BeTrue
        }

        It 'sees a failure that was not the last response in the batch' {
            # The pattern this replaced only inspected the final record, so a failure anywhere
            # earlier in the batch was invisible and every operation was reported as succeeded.
            $Operations = @(
                New-Operation -Message 'Added one' -Target 'one@contoso.com' -OperationGuid 'guid-1'
                New-Operation -Message 'Added two' -Target 'two@contoso.com' -OperationGuid 'guid-2'
                New-Operation -Message 'Added three' -Target 'three@contoso.com' -OperationGuid 'guid-3'
            )
            $Response = @(
                New-ExoError -Message 'boom' -Target 'one@contoso.com' -OperationGuid 'guid-1'
                New-ExoSuccess -OperationGuid 'guid-2'
                New-ExoSuccess -OperationGuid 'guid-3'
            )

            $Result = @(Resolve-CippExoBulkResult -Response $Response -Operations $Operations)

            $Result[0].Success | Should -BeFalse
            $Result[1].Success | Should -BeTrue
            $Result[2].Success | Should -BeTrue
        }

        It 'fails several operations independently' {
            $Operations = @(
                New-Operation -Message 'Added one' -Target 'one@contoso.com' -OperationGuid 'guid-1'
                New-Operation -Message 'Added two' -Target 'two@contoso.com' -OperationGuid 'guid-2'
                New-Operation -Message 'Added three' -Target 'three@contoso.com' -OperationGuid 'guid-3'
            )
            $Response = @(
                New-ExoError -Message 'first failure' -Target 'one@contoso.com' -OperationGuid 'guid-1'
                New-ExoError -Message 'third failure' -Target 'three@contoso.com' -OperationGuid 'guid-3'
            )

            $Result = @(Resolve-CippExoBulkResult -Response $Response -Operations $Operations)

            $Result[0].ErrorMessage | Should -Be 'first failure'
            $Result[1].Success | Should -BeTrue
            $Result[2].ErrorMessage | Should -Be 'third failure'
        }

        It 'fails every operation that shares a guid with the failed request' {
            # The owner rewrite in Invoke-EditGroup expresses several owner changes as one
            # Set-DistributionGroup call, so they stand or fall together.
            $Operations = @(
                New-Operation -Message 'Added owner A' -Target 'group-guid' -OperationGuid 'owners'
                New-Operation -Message 'Removed owner B' -Target 'group-guid' -OperationGuid 'owners'
            )
            $Response = @(New-ExoError -Message 'The executing user is not in the current organization.' -Target $null -OperationGuid 'owners')

            $Result = @(Resolve-CippExoBulkResult -Response $Response -Operations $Operations)

            $Result[0].Success | Should -BeFalse
            $Result[1].Success | Should -BeFalse
        }
    }

    Context 'Errors that cannot be pinned to one operation' {
        It 'refuses to call anything a success while an untagged error is present' {
            # Set-DistributionGroup returns an error with no target, so nothing matches it. Claiming
            # success for the rest is how a rejected owner change was reported as "Success - Added
            # owner ..." while the group kept no owners at all.
            $Operations = @(
                New-Operation -Message 'Added owner' -Target 'group-guid' -OperationGuid 'guid-1'
                New-Operation -Message 'Added member' -Target 'one@contoso.com' -OperationGuid 'guid-2'
            )
            $Response = @(New-ExoError -Message 'The executing user is not in the current organization.' -Target $null)

            $Result = @(Resolve-CippExoBulkResult -Response $Response -Operations $Operations)

            $Result[0].Success | Should -BeFalse
            $Result[1].Success | Should -BeFalse
            $Result[0].ErrorMessage | Should -Be 'The executing user is not in the current organization.'
        }

        It 'treats a guid Exchange did not recognise as unattributable' {
            $Operations = @(New-Operation -Message 'Added one' -Target 'one@contoso.com' -OperationGuid 'guid-1')
            $Response = @(New-ExoError -Message 'boom' -Target 'one@contoso.com' -OperationGuid 'some-other-guid')

            $Result = @(Resolve-CippExoBulkResult -Response $Response -Operations $Operations)

            $Result[0].Success | Should -BeFalse
        }

        It 'still attributes the error it can while failing the rest conservatively' {
            $Operations = @(
                New-Operation -Message 'Added one' -Target 'one@contoso.com' -OperationGuid 'guid-1'
                New-Operation -Message 'Added two' -Target 'two@contoso.com' -OperationGuid 'guid-2'
            )
            $Response = @(
                New-ExoError -Message 'specific failure' -Target 'one@contoso.com' -OperationGuid 'guid-1'
                New-ExoError -Message 'untagged failure' -Target $null
            )

            $Result = @(Resolve-CippExoBulkResult -Response $Response -Operations $Operations)

            $Result[0].ErrorMessage | Should -Be 'specific failure'
            $Result[1].Success | Should -BeFalse
            $Result[1].ErrorMessage | Should -Be 'untagged failure'
        }
    }

    Context 'Callers that do not tag their operations' {
        It 'falls back to matching on target' {
            $Operations = @(
                New-Operation -Message 'Added one' -Target 'one@contoso.com'
                New-Operation -Message 'Added two' -Target 'two@contoso.com'
            )
            $Response = @(New-ExoError -Message 'boom' -Target 'two@contoso.com')

            $Result = @(Resolve-CippExoBulkResult -Response $Response -Operations $Operations)

            $Result[0].Success | Should -BeTrue
            $Result[1].Success | Should -BeFalse
            $Result[1].ErrorMessage | Should -Be 'boom'
        }

        It 'fails everything when the untagged error has no target either' {
            $Operations = @(
                New-Operation -Message 'Added one' -Target 'one@contoso.com'
                New-Operation -Message 'Added two' -Target 'two@contoso.com'
            )
            $Response = @(New-ExoError -Message 'boom' -Target $null)

            $Result = @(Resolve-CippExoBulkResult -Response $Response -Operations $Operations)

            $Result[0].Success | Should -BeFalse
            $Result[1].Success | Should -BeFalse
        }
    }

    Context 'Reading the message out of an error record' {
        It 'uses a plain string error as-is' {
            $Result = @(Resolve-CippExoBulkResult -Response @(New-ExoError -Message 'plain text' -Target 'a') -Operations @(New-Operation -Message 'op' -Target 'a'))
            $Result[0].ErrorMessage | Should -Be 'plain text'
        }

        It 'digs the message out of a nested details object' {
            # Some callers hand raw Graph-shaped errors straight through rather than the flattened
            # record, and printing a type name at the operator helps nobody.
            $Response = @([pscustomobject]@{ error = [pscustomobject]@{ details = [pscustomobject]@{ message = 'nested detail' } }; target = 'a' })

            $Result = @(Resolve-CippExoBulkResult -Response $Response -Operations @(New-Operation -Message 'op' -Target 'a'))

            $Result[0].ErrorMessage | Should -Be 'nested detail'
        }

        It 'falls back to the top-level message' {
            $Response = @([pscustomobject]@{ error = [pscustomobject]@{ message = 'top level' }; target = 'a' })

            $Result = @(Resolve-CippExoBulkResult -Response $Response -Operations @(New-Operation -Message 'op' -Target 'a'))

            $Result[0].ErrorMessage | Should -Be 'top level'
        }
    }

    Context 'Degenerate input' {
        It 'returns nothing when there were no operations' {
            $Result = @(Resolve-CippExoBulkResult -Response @() -Operations @())
            $Result.Count | Should -Be 0
        }

        It 'ignores null entries in the response' {
            $Operations = @(New-Operation -Message 'Added one' -Target 'one@contoso.com' -OperationGuid 'guid-1')
            $Result = @(Resolve-CippExoBulkResult -Response @($null, (New-ExoSuccess -OperationGuid 'guid-1'), $null) -Operations $Operations)
            $Result[0].Success | Should -BeTrue
        }

        It 'treats a null response as a clean run' {
            $Operations = @(New-Operation -Message 'Added one' -Target 'one@contoso.com' -OperationGuid 'guid-1')
            $Result = @(Resolve-CippExoBulkResult -Response $null -Operations $Operations)
            $Result[0].Success | Should -BeTrue
        }
    }
}
