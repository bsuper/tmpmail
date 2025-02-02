#!/usr/bin/env sh
#
# by Siddharth Dushantha 2020
#
# Dependencies: jq, curl, w3m
#

version=1.2.3

# By default 'tmpmail' uses 'w3m' as it's web browser to render
# the HTML of the email
browser="w3m"

# The default command that will be used to copy the email address to
# the user's clipboard when running 'tmpmail --copy'
copy_to_clipboard_cmd="xclip -selection c"

# If the value is set to 'true' tmpmail will convert the HTML email
# to raw text and send that to stdout
raw_text=false

# Everything related to 'tmpmail' will be stored in /tmp/tmpmail
# so that the old emails and email addresses get cleared after
# restarting the computer
tmpmail_dir="/tmp/tmpmail"

# tmpmail_email_address is where we store the temporary email address
# that gets generated. This prevents the user from providing
# the email address everytime they run tmpmail
tmpmail_email_address="$tmpmail_dir/email_address"

# tmpmail.html is where the email gets stored.
# Even though the file ends with a .html extension, the raw text version of
# the email will also be stored in this file so that w3m and other browsers
# are able to open this file
tmpmail_html_email="$tmpmail_dir/tmpmail.html"

# Default 1secmail API URL
tmpmail_api_url="https://www.1secmail.com/api/v1/"

usage() {
    # Using 'cat << EOF' we can easily output a multiline text. This is much
    # better than using 'echo' for each line or using '\n' to create a new line.
    cat <<EOF
tmpmail
tmpmail -h | --version
tmpmail -g [ADDRESS]
tmpmail [-t | -b BROWSER] -r | ID

When called with no option and no argument, tmpmail lists the messages in
the inbox and their numeric IDs.  When called with one argument, tmpmail
shows the email message with specified ID.

-b, --browser BROWSER
        Specify BROWSER that is used to render the HTML of
        the email (default: w3m)
    --clipboard-cmd COMMAND
        Specify the COMMAND to use for copying the email address to your
        clipboard (default: xclip -selection c)
-c, --copy
        Copy the email address to your clipboard
-d, --domains
        Show list of available domains
-g, --generate [ADDRESS]
        Generate a new email address, either the specified ADDRESS, or
        randomly create one
-h, --help
        Show help
-r, --recent
        View the most recent email message
-t, --text
        View the email as raw text, where all the HTML tags are removed.
        Without this option, HTML is used.
--version
        Show version
EOF
}

get_list_of_domains() {
    # Getting domains list from 1secmail API
    data=$(curl -sL "$tmpmail_api_url?action=getDomainList") 

    # Number of available domains
    data_length=$(printf %s "$data" | jq length)

    # If the length of the data we got is 0, that means the email address
    # has not received any emails yet.
    [ "$data_length" -eq 0 ] && echo "1secmail API error for getting domains list" && exit

    # Getting rid of quotes, braces and replace comma with space
    printf "%s" "$data" | tr -d "[|]|\"" | tr "," " "
}

show_list_of_domains() {
    # Convert the list of domains which are in a singal line, into multiple lines
    # with a dash in the beginning of each domain for a clean output
    domains=$(printf "%s" "$(get_list_of_domains)" | tr " " "\n" | sed "s/^/- /g")
    printf "List of available domains: \n%s\n" "$domains"
}

generate_email_address() {
    # There are 2 ways which this function is called in this script.
    #  [1] The user wants to generate a new email and runs 'tmpmail --generate'
    #  [2] The user runs 'tmpmail' to check the inbox , but /tmp/tmpmail/email_address
    #      is empty or nonexistant. Therefore a new email gets automatically
    #      generated before showing the inbox. But of course the inbox will
    #      be empty as the newly generated email address has not been
    #      sent any emails.
    #
    # When the function 'generate_email_address()' is called with the arguement
    # 'true', it means that the function was called because the user
    # ran 'tmpmail --generate'.
    #
    # We need this variable so we can know whether or not we need to show the user
    # what the email was. <-- More about this can be found further down in this function.
    externally=${1:-false}

    # This variable lets generate_email_address know if the user has provided a custom
    # email address which they want to use. custom is set to false if $2 has no value.
    custom=${2:-false}

    # Generate a random email address.
    # This function is called whenever the user wants to generate a new email
    # address by running 'tmpmail --generate' or when the user runs 'tmpmail'
    # but /tmp/tmpmail/email_address is empty or nonexistent.
    #
    # We create a random username by taking the first 10 lines from /dev/random
    # and delete all the characters which are *not* lower case letters from A to Z.
    # So charcters such as dashes, periods, underscore, and numbers are all deleted,
    # giving us a text which only contains lower case letters form A to Z. We then take
    # the first 10 characters, which will be the username of the email address
    username=$(head /dev/urandom | LC_ALL=C tr -dc "[:alnum:]" | cut -c1-11 | tr "[:upper:]" "[:lower:]")

    # Generate a regex for valif email adress by fetching the list of supported domains
    valid_email_address_regex=$(printf "[a-z0-9]+@%s" "$(get_list_of_domains | tr ' ' '|')")
    username_black_list_regex="(abuse|webmaster|contact|postmaster|hostmaster|admin)"
    username_black_list="- abuse\n- webmaster\n- contact\n- postmaster\n- hostmaster\n- admin"

    # Randomly pick one of the domains mentioned above.
    domain=$(printf "%b" "$(get_list_of_domains)" | tr " " "\n" | randomize | tail -1)

    email_address="$username@$domain"

    # If the user provided a custom email address then use that email address
    if [ "$custom" != false ]; then
        email_address=$custom

        # Check if the user is using username in the email address which appears
        # in the black list.
        if printf %b "$email_address" | grep -Eq "$username_black_list_regex"; then
            die "For security reasons, that username cannot be used. Here are the blacklisted usernames:\n$username_black_list"
        fi

        # Do a regex check to see if the email address provided by the user is a
        # valid email address
        if ! printf %b "$email_address" | grep -Eq "$valid_email_address_regex"; then
            die "Provided email is invalid. Must match $valid_email_address_regex"
        fi
    fi

    # Save the generated email address to the $tmpmail_email_address file
    # so that it can be whenever 'tmpmail' is run
    printf %s "$email_address" >"$tmpmail_email_address"

    # If this function was called because the user wanted to generate a new
    # email address, show them the email address
    [ "$externally" = true ] && cat "$tmpmail_email_address" && printf "\n"
}

get_email_address() {
    # This function is only called once and that is when this script
    # get executed. The output of this function gets stored in $email_address
    #
    # If the file that contains the email address is empty,
    # that means we do not have an email address, so generate one.
    [ ! -s "$tmpmail_email_address" ] && generate_email_address

    # Output the email address by getting the first line of $tmpmail_email
    head -n 1 "$tmpmail_email_address"
}

list_emails() {
    # List all the received emails in a nicely formatted order
    #
    # Fetch the email data using 1secmail's API
    data=$(curl -sL "$tmpmail_api_url?action=getMessages&login=$username&domain=$domain")

    # Using 'jq' we get the length of the JSON data. From this we can determine whether or not
    # the email address has gotten any emails
    data_length=$(printf %s "$data" | jq length)

    # We are showing what email address is currently being used
    # in case the user has forgotten what the email address was.
    printf "[ Inbox for %s ]\n\n" "$email_address"

    # If the length of the data we got is 0, that means the email address
    # has not received any emails yet.
    [ "$data_length" -eq 0 ] && echo "No new mail" && exit

    # This is where we store all of our emails, which is then
    # displayed using 'column'
    inbox=""

    # Go through each mail that has been received
    index=1
    while [ $index -le "${data_length}" ]; do
        # Since arrays in JSON data start at 0, we must subtract
        # the value of $index by 1 so that we dont miss one of the
        # emails in the array
        mail_data=$(printf %s "$data" | jq -r ".[$index-1]")
        id=$(printf %s "$mail_data" | jq -r ".id")
        from=$(printf %s "$mail_data" | jq -r ".from")
        subject=$(printf %s "$mail_data" | jq -r ".subject")

        # The '||' are used as a divideder for 'column'. 'column' will use this divider as
        # a point of reference to create the division. By default 'column' uses a blank space
        # but that would not work in our case as the email subject could have multiple white spaces
        # and 'column' would split the words that are seperated by white space, in different columns.
        inbox="$inbox$id ||$from ||$subject\n"
        index=$((index + 1))
    done

    # Show the emails cleanly
    printf "%b" "$inbox" | column -t -s "||"
}

randomize() {
    # We could use 'shuf' and 'sort -R' but they are not a part of POSIX
    awk 'BEGIN {srand();} {print rand(), $0}' | \
        sort -n -k1 | cut -d' ' -f2
}

view_email() {
    # View an email by providing it's ID
    #
    # The first argument provided to this function will be the ID of the email
    # that has been received
    email_id="$1"
    data=$(curl -sL "$tmpmail_api_url?action=readMessage&login=$username&domain=$domain&id=$email_id")

    # After the data is retrieved using the API, we have to check if we got any emails.
    # Luckily 1secmail's API is not complicated and returns 'Message not found' as plain text
    # if our email address as not received any emails.
    # If we received the error message from the API just quit because there is nothing to do
    [ "$data" = "Message not found" ] && die "Message not found"

    # We pass the $data to 'jq' which extracts the values
    from=$(printf %s "$data" | jq -r ".from")
    subject=$(printf %s "$data" | jq -r ".subject")
    html_body=$(printf %s "$data" | jq -r ".htmlBody")
    attachments=$(printf %s "$data" | jq -r ".attachments | length")
    
    # If you get an email that is in pure text, the .htmlBody field will be empty and
    # we will need to get the content from .textBody instead
    [ -z "$html_body" ] && html_body="<pre>$(printf %s "$data" | jq -r ".textBody")</pre>"

    # Create the HTML with all the information that is relevant and then
    # assigning that HTML to the variable html_mail. This is the best method
    # to create a multiline variable
    html_mail=$(cat <<EOF
<pre><b>To: </b>$email_address
<b>From: </b>$from
<b>Subject: </b>$subject</pre>
$html_body

EOF
)
    
    if [ ! "$attachments" = "0" ]; then
        html_mail="$html_mail<br><b>[Attachments]</b><br>"

        index=1
        while [ "$index" -le "$attachments" ]; do
            filename=$(printf %s "$data" | jq -r ".attachments | .[$index-1] | .filename")
            link="$tmpmail_api_url?action=download&login=$username&domain=$domain&id=$email_id&file=$filename"
            html_link="<a href=$link download=$filename>$filename</a><br>"

            if [ "$raw_text" = true ]; then
                # The actual url is way too long and does not look so nice in STDOUT.
                # Therefore we will shortening it using is.gd so that it looks nicer.
                link=$(curl -s -F"url=$link" "https://is.gd/create.php?format=simple")
                html_mail="$html_mail$link  [$filename]<br>"
            else
                html_mail="$html_mail$html_link"
            fi

            index=$((index + 1))
        done
    fi

    # Save the $html_mail into $tmpmail_html_email
    printf %s "$html_mail" >"$tmpmail_html_email"

    # If the '--text' flag is used, then use 'w3m' to convert the HTML of
    # the email to pure text by removing all the HTML tags
    [ "$raw_text" = true ] && w3m -dump "$tmpmail_html_email" && exit

    # Open up the HTML file using $browser. By default,
    # this will be 'w3m'.
    $browser "$tmpmail_html_email"
}

view_email_html_body() {
    # View an email by providing it's ID
    #
    # The first argument provided to this function will be the ID of the email
    # that has been received
    email_id="$1"
    data=$(curl -sL "$tmpmail_api_url?action=readMessage&login=$username&domain=$domain&id=$email_id")

    # After the data is retrieved using the API, we have to check if we got any emails.
    # Luckily 1secmail's API is not complicated and returns 'Message not found' as plain text
    # if our email address as not received any emails.
    # If we received the error message from the API just quit because there is nothing to do
    [ "$data" = "Message not found" ] && die "Message not found"

    # We pass the $data to 'jq' which extracts the values
    from=$(printf %s "$data" | jq -r ".from")
    subject=$(printf %s "$data" | jq -r ".subject")
    html_body=$(printf %s "$data" | jq -r ".htmlBody")
    attachments=$(printf %s "$data" | jq -r ".attachments | length")
    
    # If you get an email that is in pure text, the .htmlBody field will be empty and
    # we will need to get the content from .textBody instead
    [ -z "$html_body" ] && html_body="<pre>$(printf %s "$data" | jq -r ".textBody")</pre>"

    # Create the HTML with all the information that is relevant and then
    # assigning that HTML to the variable html_mail. This is the best method
    # to create a multiline variable
    printf %s "$html_body"
#     html_mail=$(cat <<EOF
# <pre><b>To: </b>$email_address
# <b>From: </b>$from
# <b>Subject: </b>$subject</pre>
# $html_body

# EOF
# )
    
#     if [ ! "$attachments" = "0" ]; then
#         html_mail="$html_mail<br><b>[Attachments]</b><br>"

#         index=1
#         while [ "$index" -le "$attachments" ]; do
#             filename=$(printf %s "$data" | jq -r ".attachments | .[$index-1] | .filename")
#             link="$tmpmail_api_url?action=download&login=$username&domain=$domain&id=$email_id&file=$filename"
#             html_link="<a href=$link download=$filename>$filename</a><br>"

#             if [ "$raw_text" = true ]; then
#                 # The actual url is way too long and does not look so nice in STDOUT.
#                 # Therefore we will shortening it using is.gd so that it looks nicer.
#                 link=$(curl -s -F"url=$link" "https://is.gd/create.php?format=simple")
#                 html_mail="$html_mail$link  [$filename]<br>"
#             else
#                 html_mail="$html_mail$html_link"
#             fi

#             index=$((index + 1))
#         done
#     fi

#     # Save the $html_mail into $tmpmail_html_email
#     printf %s "$html_mail" >"$tmpmail_html_email"

#     # If the '--text' flag is used, then use 'w3m' to convert the HTML of
#     # the email to pure text by removing all the HTML tags
#     [ "$raw_text" = true ] && w3m -dump "$tmpmail_html_email" && exit

#     # Open up the HTML file using $browser. By default,
#     # this will be 'w3m'.
#     $browser "$tmpmail_html_email"
}

view_recent_email() {
    # View the most recent email.
    #
    # This is done by listing all the received email like you
    # normally see on the terminal when running 'tmpmail'.
    # We then grab the ID of the most recent
    # email, which the first line.
    mail_id=$(list_emails | head -3 | tail -1 | cut -d' ' -f 1)
    view_email "$mail_id"
}

view_recent_email_html_body() {
    # View the most recent email.
    #
    # This is done by listing all the received email like you
    # normally see on the terminal when running 'tmpmail'.
    # We then grab the ID of the most recent
    # email, which the first line.
    mail_id=$(list_emails | head -3 | tail -1 | cut -d' ' -f 1)
    view_email_html_body "$mail_id"
}


copy_email_to_clipboard(){
    # Copy the email thats being used to the user's clipboard
    $copy_to_clipboard_cmd < $tmpmail_email_address
}


die() {
    # Print error message and exit
    #
    # The first argument provided to this function will be the error message.
    # Script will exit after printing the error message.
    printf "%b\n" "Error: $1" >&2
    exit 1
}

main() {
    # Iterate of the array of dependencies and check if the user has them installed.
    # We are checking if $browser is installed instead of checking for 'w3m'. By doing
    # this, it allows the user to not have to install 'w3m' if they are using another
    # browser to view the HTML.
    #
    # dep_missing allows us to keep track of how many dependencies the user is missing
    # and then print out the missing dependencies once the checking is done.
    dep_missing=""

    # The main command from $copy_to_clipboard_cmd
    # Example:
    #   xclip -selection c
    #   ├───┘
    #   └ This part
    clipboard=${copy_to_clipboard_cmd%% *}

    for dependency in jq $browser $clipboard curl; do
        if ! command -v "$dependency" >/dev/null 2>&1; then
            # Append to our list of missing dependencies
            dep_missing="$dep_missing $dependency"
        fi
    done

    if [ "${#dep_missing}" -gt 0 ]; then
        printf %s "Could not find the following dependencies:$dep_missing"
        exit 1
    fi

    # Create the $tmpmail_dir directory and dont throw any errors
    # if it already exists
    mkdir -p "$tmpmail_dir"

    # Get the email address and save the value to the email_address variable
    email_address="$(get_email_address)"

    # ${VAR#PATTERN} Removes shortest match of pattern from start of a string.
    # In this case, it takes the email_address and removed everything after
    # the '@' symbol which gives us the username.
    username=${email_address%@*}

    # ${VAR%PATTERN} Remove shortest match of pattern from end of a string.
    # In this case, it takes the email_address and removes everything until the
    # period '.' which gives us the domain
    domain=${email_address#*@}

    # If no arguments are provided just the emails
    [ $# -eq 0 ] && list_emails && exit

    while [ "$1" ]; do
        case "$1" in
            --help | -h) usage && exit ;;
            --domains | -d) show_list_of_domains && exit ;;
            --generate | -g) generate_email_address true "$2" && exit ;;
            --clipboard-cmd) copy_to_clipboard_cmd="$2" ;;
            --copy | -c) copy_email_to_clipboard && exit ;;
            --browser | -b) browser="$2" ;;
            --text | -t) raw_text=true ;;
            --version) echo "$version" && exit ;;
            --recent | -r) view_recent_email && exit ;;
            --recent-html | -R) view_recent_email_html_body && exit;;
            *[0-9]*)
                # If the user provides number as an argument,
                # assume its the ID of an email and try getting
                # the email that belongs to the ID
                view_email "$1" && exit
                ;;
            -*) die "option '$1' does not exist" ;;
        esac
        shift
    done
}

main "$@"
