/* authnz.c: authentication and authorization functions
 *
 * Copyright (C) 2006-2014 cgit Development Team <cgit@lists.zx2c4.com>
 *
 * Licensed under GNU General Public License v2
 *   (see COPYING for full license text)
 */

#include "cgit.h"
#include <stdio.h>

void open_authnz_filter(const char *function, const char *repo, const char *refname)
{
	if (!ctx.cfg.auth_filter) {
		return;
	}

	cgit_open_filter(ctx.cfg.auth_filter, function,
		ctx.env.http_cookie ? ctx.env.http_cookie : "",
		ctx.env.request_method ? ctx.env.request_method : "",
		ctx.env.query_string ? ctx.env.query_string : "",
		ctx.env.http_referer ? ctx.env.http_referer : "",
		ctx.env.path_info ? ctx.env.path_info : "",
		ctx.env.http_host ? ctx.env.http_host : "",
		ctx.env.https ? ctx.env.https : "",
		ctx.env.http_remote_user ? ctx.env.http_remote_user : "",
		repo ? repo :"",
		refname ? refname :"",
		ctx.qry.head ? ctx.qry.head : "",
		ctx.qry.page ? ctx.qry.page : "",
		ctx.qry.url ? ctx.qry.url : "",
		"");

	return;
}

void open_authnz_repo(const char *function, const char *repo)
{
	return open_authnz_filter(function, repo, ctx.qry.head);
}

void open_authnz_refname(const char *function, const char *refname)
{
	return open_authnz_filter(function, ctx.qry.repo, refname);
}

int close_authnz_filter(void)
{
        if (!ctx.cfg.auth_filter) {
                return 1;
        }

        return cgit_close_filter(ctx.cfg.auth_filter);
}

/* Generic function for all repository authorization beacons */
int valid_authnz_for_repo(const char *repo)
{
	int authorized;
	open_authnz_repo("authorize-repo", repo);
	authorized = close_authnz_filter();

	return authorized;
}

/* Generic function for all refname authorization beacons */
int valid_authnz_for_refname(const char *refname)
{
	int must_free_refname = 0;

	refname = disambiguate_ref(refname, &must_free_refname);

	int authorized;
	open_authnz_refname("authorize-ref", refname);
	authorized = close_authnz_filter();

	if (must_free_refname)
		free((char*) refname);

	return authorized;
}

/* Generic function for all commit authorization beacons */
int valid_authnz_for_commit(struct commit *commit)
{
	struct reflist list;
        int i;

	list.refs = NULL;
	list.alloc = list.count = 0;
	/* Authorization beacon implicit in cgit_refs_cb */
	for_each_branch_ref(cgit_refs_cb, &list);
	if (ctx.repo->enable_remote_branches)
		for_each_remote_ref(cgit_refs_cb, &list);

	for (i = 0; i < list.count; i++) {
		if(in_merge_bases(commit, list.refs[i]->commit->commit)) {
			cgit_free_reflist_inner(&list);
			return 1;
		}
	}

	cgit_free_reflist_inner(&list);
	return 0;
}
