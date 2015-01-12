################################################################################################################################
# Name: LyncAutoOps Tool 
# Version: v1.1.0 (5/1/2015)
# Created By: Max Sanna
# Web Site: http://blog.maxsanna.com
# Contact: max(at)maxsanna.com
#
# Notes: This is a Powershell tool designed to run unattended. It can be run from Powershell directly, but you'll probably want 
#        to set up a scheduled task that runs every 12 hours.
# 		 For more information on the requirements for setting up and using this tool please visit http://blog.maxsanna.com 
#        or the relevant Technet Gallery page.
#
# Copyright: Copyright (c) 2015, Max Sanna - All rights reserved.
# Licence: 	Redistribution and use of script, source and binary forms, with or without modification, are permitted provided that 
#           the following conditions are met:
#				1) Redistributions of script code must retain the above copyright notice, this list of conditions and the following disclaimer.
#				2) Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
#				3) Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer 
#                  in the documentation and/or other materials provided with the distribution.
#			THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, 
#           BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT 
#           SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL 
#           DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; LOSS OF 
#           GOODWILL OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT 
#           (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
# Release Notes:
# 1.0.0 Initial Release.
# 1.1.0 Replaced having to use the New Lync Group DN with its SAM Account name for simplicity.
#       Added comments to the code.
# 		
################################################################################################################################

# You need to have installed the Lync 2013 Core Components for this script to work
Import-Module Lync
$Date=Get-Date
# We create a log file with today's timestamp
$Logfilepath= "Logs\LyncAutoOpsProgressLog_{0}{1:d2}{2:d2}-{3:d2}{4:d2}{5:d2}" -f $date.year,$date.month,$date.day,$date.hour,$date.minute,$date.second + ".log"
$ErrorLogfilepath= "Logs\LyncAutoOpsErrorLog_{0}{1:d2}{2:d2}-{3:d2}{4:d2}{5:d2}" -f $date.year,$date.month,$date.day,$date.hour,$date.minute,$date.second + ".log"
# We import all the config parameters
[xml]$XMLDoc = Get-Content ".\LyncAutoOps.config"
$Config = $XMLDoc.SelectNodes("/Config")

################################################################################################################################
#
#        Function: Logging
#        =============
#
#        Input Parameters: 
#        $logtext: The text string to be written to the console or to a log file
#        $logtype: The type of message to be written: normal, error, or debug
#
#        Purpose: 
#        - Writes a text string to the console and/or to log files depending on the type.
#           type=cINFO: output goes to console and the normal log file
#          type=cERROR: Output goes to Console, normal log file, and error log file
#   
#
###############################################################################################################################

function logger( $logtext, $logtype )
{

    switch($logtype)
    {
        cINFO 
        {
            write-host $logtext -b black -f green
            $logtext | Out-file $Logfilepath -append
        }  
  
        cERROR
        {
            write-host "ERROR: " $logtext -b black -f red 
            "ERROR: " + $logtext | Out-file $logfilepath -append
            "ERROR: " + $logtext | Out-file $ErrorLogfilepath -append
        }
    }
}

################################################################################################################################
#
#        Function: DirectorySearcher
#        =============
#
#        Input Parameters: 
#        $LDAPQuery: The LDAP query to search for
#        $SearchRootDN: The DN containing the root for the search to be performed
#
#        Purpose: 
#        Outputs an array of results matching LDAPQuery.
#   
#
###############################################################################################################################

function DirectorySearcher {
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true,ValueFromPipeline=$false)]
        [string]$LDAPQuery,
        
        [parameter(Mandatory=$true,ValueFromPipeline=$false)]
        [string]$SearchRootDN
    )
    PROCESS {
        try {
            $DSDomain = New-Object System.DirectoryServices.DirectoryEntry("LDAP://"+$SearchRootDN)
            $DSSearcher = New-Object System.DirectoryServices.DirectorySearcher
            $DSSearcher.SearchRoot = $DSDomain
            $DSSearcher.PageSize = 1000
            $DSSearcher.Filter = $LDAPQuery
            $DSSearcher.SearchScope = "Subtree"

            $DSPropList = "sAMAccountName","distinguishedName"
            foreach ($i in $DSPropList){$DSSearcher.PropertiesToLoad.Add($i) | Out-Null}

            $DSResults = $DSSearcher.FindAll()
        }
        Catch {
            Write-Error ("An unknown error has occurred. The specific error message is: {0}" -f $_.Exception.Message)
            Return            
        }
        return $DSResults
    
    }
}

################################################################################################################################
#
#        Function: RemoveUserFromADGroup
#        =============
#
#        Input Parameters: 
#        $ADUserDN: The distinguished name of the user to be removed from a group
#        $GroupDN: The group from which $ADuserDN needs to be removed from
#
#        Purpose: 
#        Removes one user from an active directory group of choice.
#   
#
###############################################################################################################################

function RemoveUserFromADGroup {
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [string]$ADUserDN,
        [parameter(Mandatory=$true,ValueFromPipeline=$false)]
        [string]$GroupDN
    )
    PROCESS {
        try
        {
            $objADGroup = New-Object System.DirectoryServices.DirectoryEntry("LDAP://"+$GroupDN)
            $objADGroup.Properties["member"].Remove($ADUserDN)
            $objADGroup.CommitChanges()
            $objADGroup.Close()
        }
        catch [System.DirectoryServices.DirectoryServicesCOMException]
        {
            Write-Error ("The specified group or user doesn't exist. The specific error message is: {0}" -f $_.Exception.Message)
            Return $_.Exception.Message
        }
        catch
        {
            Write-Error ("An unknown error has occurred. The specific error message is: {0}" -f $_.Exception.Message)
            Return
        }
    }
}

################################################################################################################################
#
#        Function: EnableLyncUsers
#        =============
#
#        Input Parameters: 
#        $GroupDN: The distinguished name of the AD group containing users to be enabled
#
#        Purpose: 
#        - Searches AD for users which are members of $GroupDN, have an email address set and don't have a SIP address
#        - Enables the users in Lync, either on a single pool or 50/50 on a paired pool
#        - After successful enablement it removes the users from $GroupDN
#   
#
###############################################################################################################################

function EnableLyncUsers {
    [CmdletBinding()]
    param(
        [parameter(Mandatory=$true,ValueFromPipeline=$false)]
        [string]$GroupDN
    )

    PROCESS {
        # Filter to find users in AD who are members of the new Lync users group, without SIP address and with an email configured
        # Gather the array of users
        $UserFilter = "(&(objectCategory=user)(objectClass=user)(!(msRTCSIP-PrimaryUserAddress=*))(mail=*)(memberOf=$($GroupDN)))"
        $UserArray = DirectorySearcher -LDAPQuery $UserFilter -SearchRootDN $Config.ADSettings.DNDomain
        # We check if it's a paired Lync Pool config
        if ($Config.LyncSettings.PairedPool -eq "True") {
            # We check if Lastpoolused.cfg exists, otherwise we assign the second pool to the variable, as it'll be flipped over
            if (Test-Path ".\LastUsedPool.cfg" -PathType Leaf) {
                $TargetPool = get-content ".\LastUsedPool.cfg"
            } else {
                $TargetPool = $Config.LyncSettings.SecondLyncPool
            }
        } else {
            $TargetPool = $Config.LyncSettings.FirstLyncPool
        }

        foreach ($objResult in $UserArray) {
            $objUser = $objResult.Properties
            [string]$objItem = $Config.ADSettings.NetBiosDomain + "\" + $objUser."samaccountname"
            [string]$objDN = $objuser."distinguishedname"
            $error.clear()
            # If we're in a paired pool configuration we flip over the target pool
            if($Config.LyncSettings.Pairedpool -eq "True") {
                if($TargetPool -eq $Config.LyncSettings.FirstLyncPool) {
                    $TargetPool = $Config.LyncSettings.SecondLyncPool
                } else {
                    $TargetPool = $Config.LyncSettings.FirstLyncPool
                }
            }
            # We finally enable the Lync user here
            Enable-CsUser -Identity $objItem -RegistrarPool $TargetPool -SipAddressType EmailAddress -Confirm:$False
            if($error.count -gt 0) {
                  logger ( "ERROR ENABLING THE LYNC USER ON $($TargetPool): " + $objItem + " : " + $error ) cERROR
            }
            else
            {
                logger ("LYNC USER ENABLED SUCCESSFULLY ON $($TargetPool): " + $objItem ) CINFO
                # We remove the user we just enabled from the new lync users group
                RemoveUserFromADGroup -ADUserDN $objDN -GroupDN $GroupDN
                if($error.count -gt 0) {
                    logger ("ERROR REMOVING USER FROM AD GROUP : " + $objItem ) cERROR
                }
            }
         }
         # We commit to file the last used pool for the next run
         $TargetPool | Out-file ".\LastUsedPool.cfg"
         Return $UserArray
    }
}

################################################################################################################################
#
#        Function: SuspendLyncUsers
#        =============
#
#        Input Parameters: 
#        None
#
#        Purpose: 
#        - Searches AD for users who are disabled in AD, enabled in Lync and have a SIP address set
#        - Compares the found users to the one or two paired pools stored in the configuration
#        - If the user(s) found belong to one of these two pools, they'll be suspended for Lync. Not doing this would allow
#          users to log into Lync for up to 6 months after being disabled, due to the user certificate Lync issues.
#   
#
###############################################################################################################################

function SuspendLyncUsers {
    [CmdletBinding()]
    param()

    PROCESS {
        # Filter to find users in who are disabled in AD, but enabled on Lync on either of the two pools
        # Gather the array of users
        $UserFilter = "(&(objectCategory=user)(objectClass=user)(userAccountControl:1.2.840.113556.1.4.803:=2)(msRTCSIP-UserEnabled=TRUE)(msRTCSIP-PrimaryUserAddress=sip:*))"
        $UserArray = DirectorySearcher -LDAPQuery $UserFilter -SearchRootDN $Config.ADSettings.DNDomain

        foreach ($objResult in $UserArray) {
            $objUser = $objResult.Properties
            [string]$objItem = $Config.ADSettings.NetBiosDomain + "\" + $objUser."samaccountname"
            $error.clear()
            $objLyncUser = Get-CsUser -Identity $objItem
            # We compare whether the user(s) we found belong to the one/two pools specified in the config, to avoid changing users on pools we don't manage, as it often happens in a large deployment
            If (($objLyncUser.RegistrarPool.FriendlyName -eq $Config.LyncSettings.FirstLyncPool) -or ($objLyncUser.RegistrarPool.FriendlyName -eq $Config.LyncSettings.SecondLyncPool)) {
                # We suspend the user for Lync
                Set-CsUser -Identity:$objItem -Enabled $False
                if($error.count -gt 0) {
                      logger ( "ERROR SUSPENDING THE LYNC USER: " + $objItem + " : " + $error ) cERROR
                }
                else
                {
                    logger ("LYNC USER SUSPENDED SUCCESSFULLY : " + $objItem ) CINFO
                }
            }
         }
    }
}

################################################################################################################################
#
#        Function: ReactivateLyncUsers
#        =============
#
#        Input Parameters: 
#        None
#
#        Purpose: 
#        - Searches AD for users who are enabled in AD, disabled in Lync and have a SIP address set
#        - Compares the found users to the one or two paired pools stored in the configuration
#        - If the user(s) found belong to one of these two pools, they'll be reactivated for Lync
#   
#
###############################################################################################################################

function ReactivateLyncUsers {
    [CmdletBinding()]
    param()

    PROCESS {
        # Filter to find users in who are enabled in AD, but disabled on Lync on either of the two pools
        # Gather the array of users
        $UserFilter = "(&(objectCategory=user)(objectClass=user)(!userAccountControl:1.2.840.113556.1.4.803:=2)(msRTCSIP-UserEnabled=FALSE)(msRTCSIP-PrimaryUserAddress=sip:*))"
        $UserArray = DirectorySearcher -LDAPQuery $UserFilter -SearchRootDN $Config.ADSettings.DNDomain

        foreach ($objResult in $UserArray) {
            $objUser = $objResult.Properties
            [string]$objItem = $Config.ADSettings.NetBiosDomain + "\" + $objUser."samaccountname"
            $error.clear()
            $objLyncUser = Get-CsUser -Identity $objItem
            # We compare whether the user(s) we found belong to the one/two pools specified in the config, to avoid changing users on pools we don't manage, as it often happens in a large deployment
            If (($objLyncUser.RegistrarPool.FriendlyName -eq $Config.LyncSettings.FirstLyncPool) -or ($objLyncUser.RegistrarPool.FriendlyName -eq $Config.LyncSettings.SecondLyncPool)) {
                # This line reactivates the user
                Set-CsUser -Identity:$objItem -Enabled $True
                if($error.count -gt 0) {
                      logger ( "ERROR REACTIVATING THE LYNC USER: " + $objItem + " : " + $error ) cERROR
                }
                else
                {
                    logger ("LYNC USER REACTIVATED SUCCESSFULLY : " + $objItem ) CINFO
                }
            }
         }
    }
}

################################################################################################################################
#
#        Function: DeleteLyncUsers
#        =============
#
#        Input Parameters: 
#        None
#
#        Purpose: 
#        - Searches AD for users who are disabled in AD and haven't logged on in the number of days specified in the config,
#          with a SIP address set
#        - Compares the found users to the one or two paired pools stored in the configuration
#        - If the user(s) found belong to one of these two pools, they'll be permanently deleted from Lync
#   
#
###############################################################################################################################

function DeleteLyncUsers {
    [CmdletBinding()]
    param()

    PROCESS {
        # Filter to find users in who have been disabled in AD for more than the DeleteThreshold parameter
        $oldDate = (Get-Date).AddDays("-" + $Config.ScriptFunctions.DeleteThreshold).ToFileTime().toString()
        $UserFilter = "(&(objectCategory=user)(objectClass=user)(lastLogonTimeStamp<=$oldDate)(userAccountControl:1.2.840.113556.1.4.803:=2)(msRTCSIP-PrimaryUserAddress=sip:*))"
        $UserArray = DirectorySearcher -LDAPQuery $UserFilter -SearchRootDN $Config.ADSettings.DNDomain

        foreach ($objResult in $UserArray) {
            $objUser = $objResult.Properties
            [string]$objItem = $Config.ADSettings.NetBiosDomain + "\" + $objUser."samaccountname"
            $error.clear()
            $objLyncUser = Get-CsUser -Identity $objItem
            # We compare whether the user(s) we found belong to the one/two pools specified in the config, to avoid changing users on pools we don't manage, as it often happens in a large deployment
            If (($objLyncUser.RegistrarPool.FriendlyName -eq $Config.LyncSettings.FirstLyncPool) -or ($objLyncUser.RegistrarPool.FriendlyName -eq $Config.LyncSettings.SecondLyncPool)) {
                # This line deletes the user
                Disable-CsUser -Identity:$objItem
                if($error.count -gt 0) {
                      logger ( "ERROR DELETING THE LYNC USER: " + $objItem + " - LAST LOGON TIME: " + $objtime + " : " + $error  ) cERROR
                }
                else
                {
                    logger ("LYNC USER DELETED SUCCESSFULLY : " + $objItem + " - LAST LOGON TIME " + $objtime ) CINFO
                }
            }
         }
    }
}

################################################################################################################################
#
#        Function: GrantLyncPolicies
#        =============
#
#        Input Parameters: 
#        $UserArray: The array of users who need to have their policies modified. Can also be pipelined from another cmdlet.
#
#        Purpose: 
#        - Given an array of Lync users, it will modify their user policies as specified in the config file, namely:
#          Exchange archiving policy, client policy, conferencing policy, external access policy, pin policy and archiving
#          policy. The script can be customised to assign more policies if required although they're rarely used.
#   
#
###############################################################################################################################

function GrantLyncPolicies {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$false,ValueFromPipeline=$true)]
        [System.Array]$UserArray
    )
    PROCESS {
        foreach ($objResult in $UserArray) {
            $objUser = $objResult.Properties
            [string]$objItem = $Config.ADSettings.NetBiosDomain + "\" + $objUser."samaccountname"
            $error.clear()
            # The following IF statements check whether the policy was set to something in the config. If left empty, the global policy will be left assigned.
            if ($Config.UserPolicies.ExchangeArchiving -eq "True") {
                Set-CsUser -Identity $objitem -ExchangeArchivingPolicy ArchivingToExchange
            }

            if ($Config.UserPolicies.ClientPolicy -ne "") {
                Grant-CsClientPolicy -Identity $objitem -PolicyName $Config.UserPolicies.ClientPolicy
            }

            if ($Config.UserPolicies.ConferencingPolicy -ne "") {
                Grant-CsConferencingPolicy -Identity $objitem -PolicyName $Config.UserPolicies.ConferencingPolicy
            }

            if ($Config.UserPolicies.ExternalPolicy -ne "") {
                Grant-CsExternalAccessPolicy -Identity $objitem -PolicyName $Config.UserPolicies.ExternalPolicy
            }
            
            if ($Config.UserPolicies.PinPolicy -ne "") {
                Grant-CsPinPolicy -Identity $objitem -PolicyName $Config.UserPolicies.PinPolicy
            }
            
            if ($Config.UserPolicies.ArchivingPolicy -ne "") {
                Grant-CsArchivingPolicy -Identity $objitem -PolicyName $Config.UserPolicies.ArchivingPolicy
            }

            if($error.count -gt 0)
            {
                  logger ( "ERROR SETTING POLICIES FOR THE LYNC USER: " + $objItem + " : " + $error ) cERROR
            }
            else
            {
                  logger ("LYNC USER POLICIES SET SUCCESSFULLY : " + $objItem ) CINFO
            }

        }        
    }
}

################################################################################################################################
#
#        Function: EmailNotifier
#        =============
#
#        Input Parameters: 
#        None
#
#        Purpose: 
#        - Verifies whether the log file and/or the error log file were created during the script run
#        - If they exist, the script will use the parameters from the config file to connect to the specified SMTP server
#          and send an email to the recipients contained in Recipients.txt with the logs attached
#   
#
###############################################################################################################################

function EmailNotifier {
    [CmdletBinding()]
    param()
    PROCESS {

        if (Test-Path $logfilepath -PathType Leaf) {
            [string[]]$Recipients = Get-content $Config.Notifications.Recipientspath
            Send-MailMessage -To $Recipients -From $Config.Notifications.FromAddress -Subject "Lync AutoOps Results" -body "Log file from Lync AutoOps" -SmtpServer $Config.Notifications.SMTPServer -attachments $Logfilepath -usessl 
        }

        if (Test-Path $Errorlogfilepath -PathType Leaf) {
            [string[]]$Recipients = Get-content $Config.Notifications.Recipientspath
            Send-MailMessage -To $Recipients -From $Config.Notifications.FromAddress -Subject "Lync AutoOps Error Log" -body "Error Log file from Lync AutoOps" -SmtpServer $Config.Notifications.SMTPServer -attachments $Logfilepath -usessl 
        }
    }
}

################################################### Main Script Section #######################################################

# If the configuration file was set to enable Lync users, the following block will be executed
if ($Config.ScriptFunctions.Enablement -eq "True") {
    # Here we convert the SAMAccountName of the new lync users AD group into a distinguished name
    $GroupSearcher = DirectorySearcher -SearchRootDN $Config.ADSettings.DNDomain -LDAPQuery "(&(objectCategory=group)(sAMAccountName=$($Config.ADSettings.NewLyncGroup)))"
    $GroupDN = ($GroupSearcher.Properties.distinguishedname[0]).ToString()

    # We enable the lync users and store the array temporarily
    $EnabledUsers = EnableLyncUsers -GroupDN $GroupDN
    If ($EnabledUsers -ne $Null) {
        # If users have been enabled, we sleep the script for 30 seconds to allow AD replication to happen before we assign the Lync policies
        Sleep -Seconds 30
        # Here we assign the Lync policies to the user array created above
        $EnabledUsers | GrantLyncPolicies
    }
}

# This block gets executed if the config file was set to suspend Lync users disabled in AD
if ($Config.ScriptFunctions.Suspension -eq "True") {
    SuspendLyncUsers
}

# This block gets executed if the config file was set to reactivate Lync users enabled in AD
if ($Config.ScriptFunctions.Reactivation -eq "True") {
    ReactivateLyncUsers
}

# This block gets executed if the config file was set to delete Lync users disabled in AD who haven't logged on in <x> days
if ($Config.ScriptFunctions.Deletion -eq "True") {
    DeleteLyncUsers
}

# This block gets executed if the config file was set to send email notifications for every script run
if ($Config.Notifications.EnableNotifications -eq "True") {
    EmailNotifier
}


##################################################### Script End ##############################################################