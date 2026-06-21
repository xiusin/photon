module services

// emails.v — PhotonBlog 邮件发送集成
//
// 封装邮件发送逻辑，使用 photon.mailer 的 EmailBuilder + 模板系统。

import photon.mailer
import models

// send_welcome_email 发送欢迎邮件给新注册用户
pub fn send_welcome_email(m &mailer.Mailer, user models.User) ! {
	unsafe {
		if isnil(m) {
			return error('send_welcome_email: mailer not initialized')
		}
	}

	mut mailer_inst := unsafe { mut m }
	mut builder := mailer.new_email_builder()
	builder = builder.to(user.email)
	builder = builder.subject('欢迎注册 PhotonBlog / Welcome to PhotonBlog')
	builder = builder.set_template(mailer.template_welcome())
	builder = builder.with_var('name', if user.nickname.len > 0 { user.nickname } else { user.username })
	builder = builder.with_var('app_name', 'PhotonBlog')
	builder = builder.with_var('action_url', 'https://photonblog.dev/login')
	email := builder.build()
	mailer_inst.send(email)!
}

// send_comment_notification 发送评论通知邮件给文章作者
pub fn send_comment_notification(m &mailer.Mailer, post_author models.User, post models.Post, comment models.Comment) ! {
	unsafe {
		if isnil(m) {
			return error('send_comment_notification: mailer not initialized')
		}
	}

	mut mailer_inst := unsafe { mut m }
	mut builder := mailer.new_email_builder()
	builder = builder.to(post_author.email)
	builder = builder.subject('您的文章收到了新评论 / New Comment on Your Post')
	builder = builder.set_template(mailer.template_notification())
	builder = builder.with_var('title', '新评论通知 / New Comment Notification')
	builder = builder.with_var('greeting', '您好 / Hello')
	builder = builder.with_var('name', if post_author.nickname.len > 0 { post_author.nickname } else { post_author.username })
	builder = builder.with_var('message', '您的文章《${post.title}》收到了新评论：${comment.content}')
	builder = builder.with_var('action_text', '查看评论 / View Comment')
	builder = builder.with_var('action_url', 'https://photonblog.dev/posts/${post.id}')
	builder = builder.with_var('action_label', '点击查看 / Click to View')
	email := builder.build()
	mailer_inst.send(email)!
}
