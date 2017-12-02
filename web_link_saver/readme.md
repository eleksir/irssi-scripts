## link_to_memc.pl

Script that greps http(s) links from irc conversations and put 'em to memcache on 127.0.0.1:11211

## img-save.pl

Sample memcache clients that loops every 30 seconds over stored memcache keys, downloads images and cleans up processed links

## purpose of these scripts

irssi api is not thread-safe. If you need asynchronously process something in irssi the only way to make it by using threads. But using threads cause memory leak and possibly something more bad (but i didn't observe some other side effects). Another way to make things asynchronously is to store data that should be processed in some fast storage and run separate process that hammer data from this storage.

Downloading images is time consuming task. During data transfer irssi itself becomes unresponsitive.
