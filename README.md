# lyncautoops
Lync AutoOps - Automatically manages Lync users lifecycle

Essentially the script will perform 4 functions, which are the basics of Lync user management:
- Enable Lync users who are members of an Active Directory group
    - As of version 1.5.0, the script is now pretty flexible and can support different topologies. It can either work in ‘simple’ mode and enable users either on a single pool or on a paired pool, balancing the users 50/50 on the two different pools, or it can work in the new MultiPool mode, which supports multiple pairs of Lync pools, with multiple locations assigned to them, and uses an AD attribute to identify where the user resides and on which pool to enable them.
    - After enabling the users, it will assign a number of Lync policies to all the users.
    -It will also remove the users from the AD group used for activations, so the group stays empty after usage.
- Suspend Lync users who are enabled in Lync but disabled in Active Directory. I saw many customers not realising that simply disabling someone in Active Directory doesn’t prevent them from using Lync at all, because Lync issues a client certificate that lasts 180 days. Therefore, after you disable a user in Active Directory, chances are he will be able to still use Lync on a previously-used device for another 6 months. Hardly security-conscious, is it?
- Reactivate Lync users who are disabled in Lync but enabled in Active Directory. This does the opposite: an employee may have gone in maternity for a few months, the IT department disables her account, then she comes back and gets it re-enabled. The script will re-enable these people automatically.
- Delete Lync users who are disabled in Active Directory and who haven’t logged in for a custom number of days (usually 90 is a good number). This allows the Lync team to keep the backend database tidy by removing all the users who have left the company. It’s always good practice to delete people from Lync before deleting the AD object, or a lot of ‘leftovers’ will remain in the Lync backend database.

On top of all this, it also emails a custom list of recipients the results of each script run. If there were errors, a separate log file containing only the errors will also be produced to simplify remediation.

For further information please see the attached Admin Guide in Word format.
