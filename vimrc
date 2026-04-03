" Productivity vimrc - common best practices
" Managed by J-pro-tools

" --- General ---
set nocompatible
filetype plugin indent on
syntax on
set encoding=utf-8
set fileencoding=utf-8
set backspace=indent,eol,start
set hidden
set autoread
set mouse=a
set clipboard=unnamedplus
set history=1000

" --- Display ---
set number
set relativenumber
set cursorline
set ruler
set laststatus=2
set showcmd
set showmode
set showmatch
set wildmenu
set wildmode=longest:full,full
set scrolloff=5
set sidescrolloff=5
set signcolumn=auto

" --- Indentation ---
set autoindent
set smartindent
set expandtab
set tabstop=4
set shiftwidth=4
set softtabstop=4
set shiftround

" --- Search ---
set incsearch
set hlsearch
set ignorecase
set smartcase
" Clear search highlight with Esc
nnoremap <Esc> :nohlsearch<CR><Esc>

" --- Performance ---
set lazyredraw
set ttyfast
set updatetime=300
set timeoutlen=500

" --- Files ---
set nobackup
set nowritebackup
set noswapfile
set undofile
set undodir=~/.vim/undodir

" --- Splits ---
set splitbelow
set splitright

" --- Whitespace visibility ---
set list
set listchars=tab:>-,trail:~,extends:>,precedes:<

" --- Status line ---
set statusline=%f\ %m%r%h%w\ %=%y\ [%l/%L,%c]\ %p%%

" --- Quality of life keymaps ---
" Move between splits with Ctrl+hjkl
nnoremap <C-h> <C-w>h
nnoremap <C-j> <C-w>j
nnoremap <C-k> <C-w>k
nnoremap <C-l> <C-w>l

" Move lines up/down with Alt+j/k
nnoremap <A-j> :m .+1<CR>==
nnoremap <A-k> :m .-2<CR>==
vnoremap <A-j> :m '>+1<CR>gv=gv
vnoremap <A-k> :m '<-2<CR>gv=gv

" Quick save
nnoremap <C-s> :w<CR>
inoremap <C-s> <Esc>:w<CR>a

" Create undo dir if it doesn't exist
if !isdirectory(expand('~/.vim/undodir'))
  call mkdir(expand('~/.vim/undodir'), 'p')
endif
