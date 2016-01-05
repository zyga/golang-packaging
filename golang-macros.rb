#!/usr/bin/env ruby

require 'fileutils'
require 'securerandom'
require 'find'
require '/usr/lib/rpm/golang/rpmsysinfo.rb'
include RpmSysinfo

# GLOBAL RPM MACROS

$builddir = RpmSysinfo.get_builddir
$buildroot = RpmSysinfo.get_buildroot
$libdir = RpmSysinfo.get_libdir
$go_arch = RpmSysinfo.get_arch
$go_contribdir = RpmSysinfo.get_contribdir
$go_contribsrcdir = RpmSysinfo.get_contribsrcdir
$go_tooldir = RpmSysinfo.get_tooldir

# ARGV[0], the called method itself
if ARGV[0] == "--prep"

	puts "Preparation Stage:\n"

	# ARGV[1] the import path
	if ARGV[1] == nil
		puts "[ERROR]Empty IMPORTPATH! Please specify a valid one.\n"
	else
		gopath = $builddir + "/go"
		puts "GOPATH set to: " + gopath + "\n"

		importpath = ARGV[1]
		puts "IMPORTPATH set to: " + importpath + "\n"

		# export IMPORTPATH to a temp file, as ruby can't export system environment variables
                # like shell scripts
		File.open("/tmp/importpath.txt","w") do |f|
			f.puts(importpath)
		end

		# return current directory name, eg: ruby-2.2.4
		dir = File.basename(Dir.pwd)
		destination = gopath + "/src/" + importpath
		puts "Creating " + destination + "\n"
		FileUtils.mkdir_p(destination)

		# copy everything to destination
		puts "Copying everything under " + $builddir + "/" + dir + " to " + destination + " :\n"
		Dir.glob($builddir + "/" + dir + "/*").each do |f|
			puts "Copying " + f + "\n"
			FileUtils.cp_r(f, File.join(destination, File.basename(f)))
		end
		puts "Files are moved!\n"

		# create target directories
		puts "Creating directory for binaries " + $buildroot + "/usr/bin" + "\n"  
		FileUtils.mkdir_p($buildroot + "/usr/bin")
		puts "Creating directory for contrib " + $buildroot + $go_contribdir + "\n"	
		FileUtils.mkdir_p($buildroot + $go_contribdir)
		puts "Creating directory for source " + $buildroot + $go_contribsrcdir + "\n"
		FileUtils.mkdir_p($buildroot + $go_contribsrcdir)
		puts "Creating directory for tool " + $buildroot + $go_tooldir + "\n"
		FileUtils.mkdir_p($buildroot + $go_tooldir)
	end

	puts "Preparation Finished!\n"

elsif ARGV[0] == "--build"

	puts "Build stage:\n"

	gopath = $builddir + "/go:" + $libdir + "/go/contrib"
        gobin = $builddir + "/go/bin"
	buildflags = "-s -v -p 4 -x"

	# get importpath from /tmp/importpath.txt saved by prep()
	importpath = open("/tmp/importpath.txt","r").gets.strip!

	# ARGV[0] is "--build" itself, there can be "--with-buildid" or "--shared"
        # all else are treated as MODs
	mods = ARGV
	mods.delete_at(0) # drop "--build"
	sharedflags = ""
	buildidflags = ""

	if mods.include?("--shared")
		sharedflags = "-buildmode=shared -linkshared"
		mods.delete("--shared")
	end

	if mods.include?("--with-buildid")
		buildid = "0x" + SecureRandom.hex(20)
		buildidflags = '-ldflags "-B ' + buildid + '"'
		mods.delete("--with-buildid")
	end

	# MODs: nil, "...", "/...", "foo...", "foo/...", "foo bar", "foo bar... baz" and etc
	if mods.empty?
		system("GOPATH=\"#{gopath}\" GOBIN=\"#{gobin}\" go install #{sharedflags} #{buildidflags} #{buildflags} #{importpath}")	
	else
		for mod in mods do
			if mod == "..."
				system("GOPATH=\"#{gopath}\" GOBIN=\"#{gobin}\" go install #{sharedflags} #{buildidflags} #{buildflags} #{importpath}...")
				break
			else
				system("GOPATH=\"#{gopath}\" GOBIN=\"#{gobin}\" go install #{sharedflags} #{buildidflags} #{buildflags} #{importpath}/#{mod}")
			end
		end
	end

	puts "Build Finished!\n"

elsif ARGV[0] == "--install"

	puts "Installation stage:\n"

	unless Dir["#{$builddir}/go/pkg/*"].empty?
		puts "Copying generated stuff to " + $buildroot + $go_contribdir
		Dir.glob($builddir + "/go/pkg/linux_" + $go_arch + "/*").each do |f|
			puts "Copying " + f
			FileUtils.cp_r(f, $buildroot + $go_contribdir)
		end
		puts "Done!"
	end

	unless Dir["#{$builddir}/go/bin/*"].empty?
		puts "Copyig binaries to " + $buildroot + "/usr/bin"
		Dir.glob($builddir + "/go/bin/*").each do |f|
			puts "Copying " + f
			FileUtils.chmod_R(0755,f)
			FileUtils.cp_r(f,$buildroot + "/usr/bin")
		end
		puts "Done!"
	end

	puts "Install finished!\n"

elsif ARGV[0] == "--source"

	puts "Source package creation:"

	puts "This will copy all *.go files in #{$builddir}/go/src, but resource files needed are still not copyed"

	Find.find($builddir + "/go/src") do |f|
		unless FileTest.directory?(f)
			if f.index(/\.go$/)
				puts "Copying " + f
				FileUtils.chmod_R(0644,f)

				# create the same hierarchy
				dir = $buildroot + $go_contribsrcdir + f.gsub($builddir + "/go/src",'')
				dir1 = dir.gsub(File.basename(dir),'')
				FileUtils.mkdir_p(dir1)
				FileUtils.install(f,dir1)
			end
		end
	end

	# remove previous created tmp file
	File.delete("/tmp/importpath.txt")

	puts "Source package created!"

elsif ARGV[0] == "--fix"

	puts "Fixing stuff..."

        # only "--fix" is given, no other parameters
        if ARGV.length == 1
                puts "[ERROR]gofix: please specify a valid importpath, see: go help fix"
        else
                gopath = $builddir + "/go"
                system("GOPATH=#{gopath} go fix #{ARGV[1]}...")
        end

	puts "Fixed!"

elsif ARGV[0] == "--test"

	puts "Testing codes..."

	# only "--test" is given, no other parameters
	if ARGV.length == 1
		puts "[ERROR]gotest: please specify a valid importpath, see: go help test"
	else
		gopath = $builddir + "/go:" + $libdir + "/go/contrib"
		system("GOPATH=#{gopath} go test -x #{ARGV[1]}...")
	end

	puts "Test passed!"

else

	puts "Please specify a valid method: --prep, --build, --install, --fix, --test, --source."

end
