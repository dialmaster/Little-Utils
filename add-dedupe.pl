use strict;
use warnings;
# This utility was used by myself to merge directories containing 
# large amounts of mp3s while removing any duped files, even if their filename was not the same
# while at the same time renaming any files that were different between source and dest if they
# had unique contents but the same filename.
# The reason it was done in the manner it was was to avoid unneccesary compare()'s of files since those are expensive
# (Brute force would be to simply compare() every source against every dest file, but with the 10,000+ files per directory
# I was using this on that would take a LONG time.


# Problems: Does not dedupe dest directory against itself. Does not dedupe source directory against itself.
# I did this again for speed, knowing that the individual directories to be merged probably did not have dupes.

use Getopt::Long;
use File::Compare;
use File::Basename;

my ($check, $srcdir, $destdir, $help);
GetOptions("check" => \$check,
           "s=s"   => \$srcdir,
           "d=s"   => \$destdir,
           "help"  => \$help);

if (!$srcdir || !$destdir || $help) {
    print qq|
        Description: Utility to copy all files from source dir to
            dest dir, deduping any files that were the same and renaming
            any that had a name collision with an existing file.
        
        Command Line Parameters:
            --check: Run in check mode only, reporting but not moving or 
                deleting any files (optional)
            --s <Source Directory> (required)
            --d <Dest Directory>   (required)|;
    exit;
}


if (! -e "$srcdir") {
    print "Source directory '$srcdir' does not exist. Please specify a valid source directory.\n";
    exit;
}
if (! -e "$destdir") {
    print "Destination directory '$destdir' does not exist. Please specify a valid destination directory.\n";
    exit;
}

if ($srcdir eq $destdir) {
    print "Source directory '$srcdir' and destination directory '$destdir' are the same! Nothing to do here...\n";
    exit;
}

opendir(SRCDIR,"$srcdir") || die "Error opening source directory '$srcdir': $!\n";

my @srcdir = readdir(SRCDIR);
# Hey now, we only want to operate on FILES here!
my @srcfiles = grep { -f ("$srcdir/$_")} @srcdir;

if (! @srcfiles) {
    print "Source directory '$srcdir' contained no files, aborting.\n";
    exit;
}

my $num = @srcfiles;
print "\nCopying $num files from $srcdir to $destdir while deduping and \nrenaming any new files with a filename collision to destination\n\n";


opendir(DESTDIR, "$destdir") || die "Error opening destination directory: $!\n";

my @destdir = readdir(DESTDIR);
my @destfiles = grep { -f ("$destdir/$_")} @destdir;

my %desthash;
# Make a hash of the dest array for easier comparison
map { $desthash{$_} = 1 } @destfiles;

# For SIZE comparison now I need to make a hash of dest files with
# SIZE as the key and then an ARRAY of the filenames that match that size as the value
my %destsizes;
foreach my $file(@destfiles){
    my $size= -s "$destdir/$file"; 
    $destsizes{$size}=() if (!$destsizes{$size});
    push(@{$destsizes{$size}},$file);
}

my ($added, $renamed, $deleted) = (0,0,0);
foreach my $file (@srcfiles) {
    # If there is already a dest file with the same name then
    # check and see if they are the same
    if ($desthash{$file}) {
#        my $compare_result = compare("$srcdir/$file", "$destdir/$file");
        my $compare_result = comparefiles("$srcdir/$file", "$destdir/$file");

        if ( $compare_result == 0) { # Files were the same, delete dupe
            if ($check) {
                print "Duped file. $destdir/$file is the same as $srcdir/$file! Would delete $srcdir/$file.\n";
            } else {
                print "Duped file. Deleted dupe of $destdir/$file $srcdir/$file.\n";
                unlink("$srcdir/$file");
            }
            $deleted += 1;
        } elsif ($compare_result == 1) { # Files were different, alter filename and move file
            
            my ($num, $newname);
            
            # Loop here to make sure and pick a unique filename. There's probably a better way to do this,
            # but this is an edge case for me
            do {
                $num = int(rand(10000)+rand(10000) + 300); 
                $newname = "$num$file";
	    } while (-e "$srcdir/$newname");

            if ($check) {
                print "Duped name but new file. Will move $srcdir/$file to $destdir/$newname.\n";
            } else {
                print "Duped name but new file. Moving $srcdir/$file to $destdir/$newname.\n";
                rename("$srcdir/$file", "$destdir/$newname");
            }
            $renamed += 1;
            $added +=1;
        } else { # Compare function failed, SKIP file and report the problem
	    print "Error '$!' comparing the files $srcdir/$file and $destdir/$file. $srcdir/$file will not be moved.\n";
	}

    } else {
        # Before we decide that this is a unique file, we need to actually compare it against any other files of
        # the same size in the dest directory as well
        my $removed = 0;
        my $size = -s "$srcdir/$file";
        if ($destsizes{$size}) {
            foreach my $comparefile (@{$destsizes{$size}}) {
                if (compare("$srcdir/$file", "$destdir/$comparefile") == 0) {
                    if ($check) {
                        print "Duped file contents. $srcdir/$file is the same as $destdir/$comparefile. Would delete dupe from $srcdir.\n"; 
                    } else {
                        print "Duped file contents. $srcdir/$file is the same as $destdir/$comparefile. Deleting dupe from $srcdir.\n";
                        unlink("$srcdir/$file");
                    }
                    $removed = 1;
                    $deleted+=1;
                    last;
                }
            }
        }
         
        if (!$removed) {
            # Actually move file from src to dest
            if ($check) {
                print "New file. Would have moved  file $srcdir/$file to $destdir/$file\n";
            } else {
                print "New file. Moved file $srcdir/$file to $destdir/$file\n";
                rename("$srcdir/$file", "$destdir/$file");
            }
            $added += 1;
        }
        
    }
}

print "\n--------\n\n";

if ($check) {
    print "Would have renamed $renamed files before move due to filename collision.\n";
    print "Would have added $added new files.\n";
    print "Would have deleted $deleted duped files.\n";
} else {
    print "Renamed $renamed files before move due to filename collision.\n";
    print "Added $added new files.\n";
    print "Deleted $deleted duped files.\n";

}


# If we can't use File::Compare, lets roll our own compare function!
# Return -1 on failure to open files, 0 if they are same, 1 if the different.
sub comparefiles {
    my $file1 = shift;
    my $file2 = shift;

    open FILE1, "$file1" or return -1;
    open FILE2, "$file2" or return -1;    

    # Just walk through each file, comparing line by line...
    while (my $file1line = <FILE1>) {
        if (eof(FILE2)) {
            close FILE1; close FILE2;
            return 1;
        } 

	my $file2line = <FILE2>;
        if ($file1line ne $file2line) {
            close FILE1; close FILE2;
            return 1;
        }
    }

    close FILE1; close FILE2;
    return 0;
}