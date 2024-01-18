#region functions
function Get-LisaAccessToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string]
        $TenantId,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string]
        $ClientId,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string]
        $ClientSecret,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string]
        $Scope,

        [Parameter()]
        [switch]
        $AsSecureString
    )

    try {
        $SplatParams = @{
            Uri         = "https://login.microsoftonline.com/$($TenantId)/oauth2/v2.0/token/"
            ContentType = "application/x-www-form-urlencoded"
            Method      = "Post"
            Body        = @{
                grant_type    = "client_credentials"
                client_id     = $ClientId
                client_secret = $ClientSecret
                scope         = $Scope
            }
        }
        $Response = Invoke-RestMethod @SplatParams

        if ($AsSecureString) {
            Write-Output ($Response.access_token | ConvertTo-SecureString -AsPlainText)
        }
        else {
            Write-Output ($Response.access_token)
        }
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($PSItem)
    }
}


function Resolve-ErrorMessage {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]
        $ErrorObject
    )

    process {
        $Exception = [PSCustomObject]@{
            FullyQualifiedErrorId = $ErrorObject.FullyQualifiedErrorId
            MyCommand             = $ErrorObject.InvocationInfo.MyCommand
            RequestUri            = $ErrorObject.TargetObject.RequestUri
            ScriptStackTrace      = $ErrorObject.ScriptStackTrace
            ErrorMessage          = $Null
            VerboseErrorMessage   = $Null
        }

        switch ($ErrorObject.Exception.GetType().FullName) {
            "Microsoft.PowerShell.Commands.HttpResponseException" {
                $Exception.ErrorMessage = $ErrorObject.ErrorDetails.Message
                break
            }
            "System.Net.WebException" {
                $Exception.ErrorMessage = [System.IO.StreamReader]::new(
                    $ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
                break
            }
            default {
                $Exception.ErrorMessage = $ErrorObject.Exception.Message
            }
        }

        $Exception.VerboseErrorMessage = @(
            "Error at Line [$($ErrorObject.InvocationInfo.ScriptLineNumber)]: $($ErrorObject.InvocationInfo.Line)."
            "ErrorMessage: $($Exception.ErrorMessage) [$($ErrorObject.ErrorDetails.Message)]"
        ) -Join " "

        Write-Output $Exception
    }
}
#endregion functions


#region Aliasses
$Config = $ActionContext.Configuration
$Account = $OutputContext.Data
$AuditLogs = $OutputContext.AuditLogs

$Person = $PersonContext.Person
$Manager = $PersonContext.Manager
#endregion Aliasses


# Start Script
try {
    # Formatting Headers and authentication for KPN Lisa Requests
    $LisaRequest = @{
        Authentication = "Bearer"
        Token          = $Config.AzureAD | Get-LisaAccessToken -AsSecureString
        ContentType    = "application/json; charset=utf-8"
        Headers        = @{
            "Mwp-Api-Version" = "1.0"
        }
    }

    #region Correlation
    if ($ActionContext.CorrelationConfiguration.Enabled) {
        $CorrelationField = $ActionContext.CorrelationConfiguration.accountField
        $CorrelationValue = $ActionContext.CorrelationConfiguration.PersonFieldValue

        if ($Null -eq $CorrelationField -or $Null -eq $CorrelationValue) {
            throw "Correlation is enabled but not configured correctly."
        }

        #  Write logic here that checks if the account can be correlated in the target system
        $SplatParams = @{
            Uri    = "$($Config.BaseUrl)/Users"
            Method = "Get"
            Body   = @{
                filter = "$($CorrelationField) eq '$($CorrelationValue)'"
            }
        }
        $CorrelatedAccount = Invoke-RestMethod @LisaRequest @SplatParams

        if ($CorrelatedAccount.count -gt 1) {
            throw "Multiple accounts found with filter: $($SplatParams.Body.filter)"
        }

        if ($CorrelatedAccount.count -eq 1) {
            $CorrelatedAccount = $CorrelatedAccount.value

            $OutputContext.AccountReference = $CorrelatedAccount.id

            $Account.PSObject.Properties | ForEach-Object {
                if ($CorrelatedAccount.PSobject.Properties.Name.Contains($PSItem.Name)) {
                    $Account.$($PSItem.Name) = $CorrelatedAccount.$($PSItem.Name)
                }
            }

            $AuditLogs.Add([PSCustomObject]@{
                    Action  = "CorrelateAccount" # Optionally specify a different action for this audit log
                    Message = "Correlated account with username $($CorrelatedAccount.UserName) on field $($CorrelationField) with value $($CorrelationValue)"
                    IsError = $False
                })

            $OutputContext.Success = $True
            $OutputContext.AccountCorrelated = $True
        }
    }
    #endregion correlation

    # Create KPN Lisa Account
    if (-Not $OutputContext.AccountCorrelated) {

        $CreationProperties = @(
            "changePasswordNextSignIn", "usageLocation", "preferredLanguage",
            "givenName", "surName", "displayName", "userPrincipalName"
        )

        Write-Verbose -Verbose "Creating KPN Lisa account for '$($Person.DisplayName)'"

        if ($Account.PSobject.Properties.Name.Contains("mail") -and $Null -eq $Account.mail) {
            $Account.mail = $Account.userPrincipalName
        }

        $Body = $Account | Select-Object $CreationProperties

        $SplatParams = @{
            Uri    = "$($Config.BaseUrl)/Users"
            Method = "Post"
            Body   = $Body
        }

        if (-Not ($ActionContext.DryRun -eq $True)) {
            $UserResponse = Invoke-RestMethod @LisaRequest @SplatParams
        }
        else {
            Write-Verbose -Verbose ($Body | ConvertTo-Json)
        }

        $OutputContext.AccountReference = $UserResponse.objectId

        $Account | Add-Member -NotePropertyMembers @{
            password = $UserResponse.temporaryPassword
        } -Force

        #Update the user with all other props
        $Body = $Account | Select-Object -Property *, "accountEnabled" -ExcludeProperty @(
            $CreationProperties, "password"
        )

        # Force the account disabled
        $Body.accountEnabled = $False

        $SplatParams = @{
            Uri    = "$($config.BaseUrl)/Users/$($OutputContext.AccountReference)/bulk"
            Method = "Patch"
            Body   = $Body
        }

        if (-Not ($ActionContext.DryRun -eq $True)) {
            [void] (Invoke-RestMethod @LisaRequest @SplatParams)
        }
        else {
            Write-Verbose -Verbose ($Body | ConvertTo-Json)
        }

        $AuditLogs.Add([PSCustomObject]@{
                Action  = "CreateAccount" # Optionally specify a different action for this audit log
                Message = "Created account for '$($Person.DisplayName)'. Id: $($OutputContext.AccountReference)"
                IsError = $False
            })

        # Set the manager
        if ($ActionContext.References.ManagerAccount) {
            $SplatParams = @{
                Uri    = "$($Config.BaseUrl)/Users/$($OutputContext.AccountReference)/Manager"
                Method = "Put"
                Body   = $ActionContext.References.ManagerAccount
            }

            if (-Not ($ActionContext.DryRun -eq $True)) {
                [void] (Invoke-RestMethod @LisaRequest @SplatParams)
            }

            $AuditLogs.Add([PSCustomObject]@{
                    Action  = "CreateAccount" # Optionally specify a different action for this audit log
                    Message = "Added Manager $($Manager.displayName) to '$($Person.DisplayName)'"
                    IsError = $False
                })
        }

        $OutputContext.Success = $True
    }
}
catch {
    $Exception = $PSItem | Resolve-ErrorMessage

    Write-Verbose -Verbose $Exception.VerboseErrorMessage

    $AuditLogs.Add([PSCustomObject]@{
            Action  = "CreateAccount" # Optionally specify a different action for this audit log
            Message = "Error creating account [$($Person.DisplayName)]. Error Message: $($Exception.ErrorMessage)."
            IsError = $True
        })
}
