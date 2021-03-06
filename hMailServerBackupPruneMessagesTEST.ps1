<#

.SYNOPSIS
	Prune Messages

.DESCRIPTION
	Delete messages in specified folders older than N days

.FUNCTIONALITY
	Looks for folder name match at any folder level and if found, deletes all messages older than N days within that folder and all subfolders within
	Deletes empty subfolders within matching folders if DeleteEmptySubFolders set to True in config

.PARAMETER 

	
.NOTES
	Folder name matching occurs at any level folder
	Empty folders are assumed to be trash if they're located in this script
	Only empty folders found in levels BELOW matching level will be deleted
	
.EXAMPLE


#>

<###   USER VARIABLES   ###>
$hMSAdminPass          = "secretpassword" # hMailServer Admin password
$DoDelete              = $False           # FOR TESTING - set to false to run and report results without deleting messages and folders
$PruneSubFolders       = $True            # True will prune all folders in levels below name matching folders
$DeleteEmptySubFolders = $True            # True will delete empty subfolders below the matching level unless a subfolder within contains messages
$DaysBeforeDelete      = 30               # Number of days to keep messages in pruned folders
$PruneFolders          = "2nd level test|2020-[0-1][0-9]-[0-3][0-9]$|Trash|Deleted|Junk|Spam|Unsubscribes"  # Names of IMAP folders you want to cleanup - uses regex

<#  Functions copied from hMailServer Backup required for testing  #>
Function Debug ($DebugOutput) {Write-Host $DebugOutput}
Function Email ($DebugOutput) {}
Function ElapsedTime ($EndTime) {
	$TimeSpan = New-Timespan $EndTime
	If (([int]($TimeSpan).Hours) -eq 0) {$Hours = ""} ElseIf (([int]($TimeSpan).Hours) -eq 1) {$Hours = "1 hour "} Else {$Hours = "$([int]($TimeSpan).Hours) hours "}
	If (([int]($TimeSpan).Minutes) -eq 0) {$Minutes = ""} ElseIf (([int]($TimeSpan).Minutes) -eq 1) {$Minutes = "1 minute "} Else {$Minutes = "$([int]($TimeSpan).Minutes) minutes "}
	If (([int]($TimeSpan).Seconds) -eq 1) {$Seconds = "1 second"} Else {$Seconds = "$([int]($TimeSpan).Seconds) seconds"}
	If (($TimeSpan).TotalSeconds -lt 1) {
		$Return = "less than 1 second"
	} Else {
		$Return = "$Hours$Minutes$Seconds"
	}
	Return $Return
}
Function Plural ($Integer) {
	If ($Integer -eq 1) {$S = ""} Else {$S = "s"}
	Return $S
}

<#  Begin hMailServerBackupPruneMessages  #>

Set-Variable -Name TotalDeletedMessages -Value 0 -Option AllScope
Set-Variable -Name TotalDeletedFolders -Value 0 -Option AllScope
Set-Variable -Name DeleteMessageErrors -Value 0 -Option AllScope
Set-Variable -Name DeleteFolderErrors -Value 0 -Option AllScope

Function GetSubFolders ($Folder) {
	$IterateFolder = 0
	$ArrayDeletedFolders = @()
	If ($Folder.SubFolders.Count -gt 0) {
		Do {
			$SubFolder = $Folder.SubFolders.Item($IterateFolder)
			$SubFolderName = $SubFolder.Name
			$SubFolderID = $SubFolder.ID
			If ($SubFolder.Subfolders.Count -gt 0) {GetSubFolders $SubFolder} 
			If ($SubFolder.Messages.Count -gt 0) {
				If ($PruneSubFolders) {GetMessages $SubFolder}
			} Else {
				If ($DeleteEmptySubFolders) {$ArrayDeletedFolders += $SubFolderID}
			} 
			$IterateFolder++
		} Until ($IterateFolder -eq $Folder.SubFolders.Count)
	}
	If ($DeleteEmptySubFolders) {
		$ArrayDeletedFolders | ForEach {
			$CheckFolder = $Folder.SubFolders.ItemByDBID($_)
			$FolderName = $CheckFolder.Name
			If (SubFoldersEmpty $CheckFolder) {
				Try {
					If ($DoDelete) {$Folder.SubFolders.DeleteByDBID($_)}
					$TotalDeletedFolders++
					Debug "Deleted empty subfolder $FolderName in $AccountAddress"
				}
				Catch {
					$DeleteFolderErrors++
					Debug "[ERROR] Deleting empty subfolder $FolderName in $AccountAddress"
					Debug "[ERROR] : $Error"
				}
				$Error.Clear()
			}
		}
	}
	$ArrayDeletedFolders.Clear()
}

Function SubFoldersEmpty ($Folder) {
	$IterateFolder = 0
	If ($Folder.SubFolders.Count -gt 0) {
		Do {
			$SubFolder = $Folder.SubFolders.Item($IterateFolder)
			If ($SubFolder.Messages.Count -gt 0) {
				Return $False
				Break
			}
			If ($SubFolder.SubFolders.Count -gt 0) {
				SubFoldersEmpty $SubFolder
			}
			$IterateFolder++
		} Until ($IterateFolder -eq $Folder.SubFolders.Count)
	} Else {
		Return $True
	}
}

Function GetMatchFolders ($Folder) {
	$IterateFolder = 0
	If ($Folder.SubFolders.Count -gt 0) {
		Do {
			$SubFolder = $Folder.SubFolders.Item($IterateFolder)
			$SubFolderName = $SubFolder.Name
			If ($SubFolderName -match [regex]$PruneFolders) {
				GetSubFolders $SubFolder
				GetMessages $SubFolder
			} Else {
				GetMatchFolders $SubFolder
			}
			$IterateFolder++
		} Until ($IterateFolder -eq $Folder.SubFolders.Count)
	}
}

Function GetMessages ($Folder) {
	$IterateMessage = 0
	$ArrayMessagesToDelete = @()
	$DeletedMessages = 0
	If ($Folder.Messages.Count -gt 0) {
		Do {
			$Message = $Folder.Messages.Item($IterateMessage)
			If ($Message.InternalDate -lt ((Get-Date).AddDays(-$DaysBeforeDelete))) {
				$ArrayMessagesToDelete += $Message.ID
			}
			$IterateMessage++
		} Until ($IterateMessage -eq $Folder.Messages.Count)
	}
	$ArrayMessagesToDelete | ForEach {
		$AFolderName = $Folder.Name
		Try {
			If ($DoDelete) {$Folder.Messages.DeleteByDBID($_)}
			$DeletedMessages++
			$TotalDeletedMessages++
		}
		Catch {
			$DeleteMessageErrors++
			Debug "[ERROR] Deleting messages from folder $AFolderName in $AccountAddress"
			Debug "[ERROR] $Error"
		}
		$Error.Clear()
	}
	If ($DeletedMessages -gt 0) {
		Debug "Deleted $DeletedMessages message$(Plural $DeletedMessages) from $AFolderName in $AccountAddress"
	}
	$ArrayMessagesToDelete.Clear()
}

Function PruneMessages {
	
	$Error.Clear()
	$BeginDeletingOldMessages = Get-Date
	Debug "----------------------------"
	Debug "Begin deleting messages older than $DaysBeforeDelete days"
	If (-not($DoDelete)) {
		Debug "Delete disabled - Test Run ONLY"
	}

	<#  Authenticate hMailServer COM  #>
	$hMS = New-Object -COMObject hMailServer.Application
	$hMS.Authenticate("Administrator", $hMSAdminPass) | Out-Null
	
	$IterateDomains = 0
	Do {
		$hMSDomain = $hMS.Domains.Item($IterateDomains)
		If ($hMSDomain.Active) {
			$IterateAccounts = 0
			Do {
				$hMSAccount = $hMSDomain.Accounts.Item($IterateAccounts)
				If ($hMSAccount.Active) {
					$AccountAddress = $hMSAccount.Address
					$IterateIMAPFolders = 0
					If ($hMSAccount.IMAPFolders.Count -gt 0) {
						Do {
							$hMSIMAPFolder = $hMSAccount.IMAPFolders.Item($IterateIMAPFolders)
							If ($hMSIMAPFolder.Name -match [regex]$PruneFolders) {
								If ($hMSIMAPFolder.SubFolders.Count -gt 0) {
									GetSubFolders $hMSIMAPFolder
								} # IF SUBFOLDER COUNT > 0
								GetMessages $hMSIMAPFolder
							} # IF FOLDERNAME MATCH REGEX
							Else {
								GetMatchFolders $hMSIMAPFolder
							} # IF NOT FOLDERNAME MATCH REGEX
						$IterateIMAPFolders++
						} Until ($IterateIMAPFolders -eq $hMSAccount.IMAPFolders.Count)
					} # IF IMAPFOLDER COUNT > 0
				} #IF ACCOUNT ACTIVE
				$IterateAccounts++
			} Until ($IterateAccounts -eq $hMSDomain.Accounts.Count)
		} # IF DOMAIN ACTIVE
		$IterateDomains++
	} Until ($IterateDomains -eq $hMS.Domains.Count)

	If ($DeleteMessageErrors -gt 0) {
		Debug "Finished Message Pruning : $DeleteMessageErrors Errors present"
		Email "[ERROR] Message Pruning : $DeleteMessageErrors Errors present : Check debug log"
	} Else {
		If ($TotalDeletedMessages -gt 0) {
			Debug "Finished pruning $TotalDeletedMessages message$(Plural $TotalDeletedMessages) in $(ElapsedTime $BeginDeletingOldMessages)"
			Email "[OK] Finished pruning $TotalDeletedMessages message$(Plural $TotalDeletedMessages) in $(ElapsedTime $BeginDeletingOldMessages)"
		} Else {
			Debug "No messages older than $DaysBeforeDelete days to prune"
			Email "[OK] No messages older than $DaysBeforeDelete days to prune"
		}
	}
	If ($DeleteFolderErrors -gt 0) {
		Debug "Deleting Empty Folders : $DeleteFolderErrors Error$(Plural $DeleteFolderErrors) present"
		Email "[ERROR] Deleting Empty Folders : $DeleteFolderErrors Error$(Plural $DeleteFolderErrors) present : Check debug log"
	} Else {
		If ($TotalDeletedFolders -gt 0) {
			Debug "Finished deleting $TotalDeletedFolders empty subfolder$(Plural $TotalDeletedFolders)"
			Email "[OK] Deleted $TotalDeletedFolders empty subfolder$(Plural $TotalDeletedFolders)"
		} Else {
			Debug "No empty subfolders deleted"
			Email "[OK] No empty subfolders deleted"
		}
	}
}

PruneMessages