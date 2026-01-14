#!/bin/bash

# Setup ZSH Environment - Fix missing oh-my-zsh plugins and tools
# Created: January 14, 2026
# For: Jordan Koch

set -e  # Exit on error

echo "🔧 Setting up ZSH environment and fixing missing plugins..."
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "${RED}❌ This script is designed for macOS${NC}"
    exit 1
fi

# Function to print status
print_status() {
    echo -e "${GREEN}✅${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠️${NC} $1"
}

print_error() {
    echo -e "${RED}❌${NC} $1"
}

# 1. Install Homebrew if not present
echo "📦 Checking Homebrew..."
if ! command -v brew &> /dev/null; then
    echo "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    print_status "Homebrew installed"
else
    print_status "Homebrew already installed"
fi

# 2. Install oh-my-zsh if not present
echo ""
echo "📦 Checking oh-my-zsh..."
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    echo "Installing oh-my-zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    print_status "oh-my-zsh installed"
else
    print_status "oh-my-zsh already installed"
fi

# 3. Install oh-my-zsh plugins
echo ""
echo "📦 Installing oh-my-zsh plugins..."

# zsh-completions
if [ ! -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-completions" ]; then
    echo "Installing zsh-completions..."
    git clone https://github.com/zsh-users/zsh-completions ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-completions
    print_status "zsh-completions installed"
else
    print_status "zsh-completions already installed"
fi

# zsh-autosuggestions
if [ ! -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions" ]; then
    echo "Installing zsh-autosuggestions..."
    git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
    print_status "zsh-autosuggestions installed"
else
    print_status "zsh-autosuggestions already installed"
fi

# zsh-syntax-highlighting
if [ ! -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting" ]; then
    echo "Installing zsh-syntax-highlighting..."
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
    print_status "zsh-syntax-highlighting installed"
else
    print_status "zsh-syntax-highlighting already installed"
fi

# 4. Create .ssh directory if missing
echo ""
echo "📦 Checking .ssh directory..."
if [ ! -d "$HOME/.ssh" ]; then
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    print_status ".ssh directory created"
else
    print_status ".ssh directory exists"
fi

# 5. Install command-line tools via Homebrew
echo ""
echo "📦 Installing command-line tools..."

# tmux
if ! command -v tmux &> /dev/null; then
    echo "Installing tmux..."
    brew install tmux
    print_status "tmux installed"
else
    print_status "tmux already installed"
fi

# direnv
if ! command -v direnv &> /dev/null; then
    echo "Installing direnv..."
    brew install direnv
    print_status "direnv installed"
else
    print_status "direnv already installed"
fi

# fzf
if ! command -v fzf &> /dev/null; then
    echo "Installing fzf..."
    brew install fzf
    # Install fzf shell extensions
    $(brew --prefix)/opt/fzf/install --all --no-bash --no-fish
    print_status "fzf installed with shell extensions"
else
    print_status "fzf already installed"
fi

# thefuck
if ! command -v thefuck &> /dev/null; then
    echo "Installing thefuck..."
    brew install thefuck
    print_status "thefuck installed"
else
    print_status "thefuck already installed"
fi

# 6. Install Powerlevel10k theme
echo ""
echo "📦 Installing Powerlevel10k theme..."
if [ ! -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k" ]; then
    echo "Installing Powerlevel10k..."
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k
    print_status "Powerlevel10k installed"
else
    print_status "Powerlevel10k already installed"
fi

# 7. Install recommended fonts for Powerlevel10k
echo ""
echo "📦 Installing Meslo Nerd Font (recommended for Powerlevel10k)..."
if ! brew list --cask font-meslo-lg-nerd-font &> /dev/null; then
    brew tap homebrew/cask-fonts
    brew install --cask font-meslo-lg-nerd-font
    print_status "Meslo Nerd Font installed"
    print_warning "Please set your terminal font to 'MesloLGS NF' in Terminal preferences"
else
    print_status "Meslo Nerd Font already installed"
fi

echo ""
echo "════════════════════════════════════════════════════════════════"
echo -e "${GREEN}✅ Setup Complete!${NC}"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "📝 Next Steps:"
echo ""
echo "1. Restart your terminal or run: source ~/.zshrc"
echo ""
echo "2. If using Powerlevel10k for the first time, run: p10k configure"
echo "   (This will guide you through theme customization)"
echo ""
echo "3. Set your terminal font to 'MesloLGS NF' in Terminal → Preferences → Profiles"
echo ""
echo "4. Your .zshrc is already synced from DotSync - no changes needed!"
echo ""
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "Installed components:"
echo "  • oh-my-zsh"
echo "  • zsh-completions plugin"
echo "  • zsh-autosuggestions plugin"
echo "  • zsh-syntax-highlighting plugin"
echo "  • Powerlevel10k theme"
echo "  • tmux"
echo "  • direnv"
echo "  • fzf (fuzzy finder)"
echo "  • thefuck (command corrector)"
echo "  • Meslo Nerd Font"
echo ""
