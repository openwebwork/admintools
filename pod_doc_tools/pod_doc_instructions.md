## instructions for pod documents with jason

/home/jaubrey/webwork:

* ww-make-docs-from-svn
	* 

* ww-make-docs
	* 	updates local copy and writes web pages

* source files
* /home/jaubrey/webwork/webwork2_TRUNK
* /home/jaubrey/webwork/pg_TRUNK     ... 

* update these directories `ls m`
* manually using `git` 
* then run `ww-make-docs-from-svn`


Need to rewrite script so that it updates
the git repository automatically.



## media wiki search daemon
/usr/local/search/ls2/  generates the search file
for mediawiki

.lsearchd   (daemon)
/etc/init/d/lsearchd

/usr/share/mediawiki  contents of media wiki
/var/lib/mediawiki  
```
mgage@ws4doc:/home/jaubrey$ sudo crontab -l -u root
ls # m h  dom mon dow   command
00  00  *   *   *   cd /usr/local/search/ls2/ && ./build > /home/jaubrey/cronlogs/lucene_search.log
00   *  *   *   *  /usr/bin/python /var/www/planet/planet.py /var/www/planet/webwork/config.ini
```
/var/www/w has some mediawiki stuff

cd /usr/local/search/ls2
sudo ./configure /var/lib/mediawiki
sudo ./build lsearch.con